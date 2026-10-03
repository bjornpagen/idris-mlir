// idr-tail-calls: every call the program makes in tail position on a cycle
// of calls is a guaranteed tail call, so that a recursion through such calls
// runs in constant stack. Scheme mandates proper tail calls, so Idris's Chez
// backend has them, and an IO loop or a mutual recursion in tail position
// must not grow the stack here either; idr-tail-loops makes only a
// function's calls of itself loops.
//
// The pass runs last, on the LLVM dialect, where the control flow is final.
//
//   - Which calls. A call in tail position matters where its callee is on
//     its caller's cycle of calls: a recursion keeps a frame per round
//     unless each of its calls is a tail call. A call from one cycle to
//     another adds its caller's frame once at most, since the callee never
//     calls back, so it is left an ordinary call, which costs nothing. The
//     cycles are those of direct calls: no call through a pointer is a tail
//     call, so a cycle through one keeps that call's frame anyway.
//   - The calling convention. The caller and the callee of such a call take
//     LLVM's `tailcc`, and so do all their calls: fastcc's registers, with
//     the guarantee that a call in tail position is a tail call, whose stack
//     arguments the callee pops. The popping costs every call of such a
//     function (on x86-64 a slot that keeps the stack aligned, which the
//     callee pops even when there is no stack argument and the caller takes
//     back), so the other functions keep C's convention, which LLVM makes
//     fastcc. Only a function that only the module's own calls reach
//     (private, its address never taken) takes `tailcc`: @main,
//     @__idr_main, which the runtime's entry calls through a pointer, and
//     in compile-time evaluation the evaluator's entries and the code of
//     closures, which an apply calls through a pointer, keep C's. Calls of
//     the runtime's C functions stay calls of C: the runtime never calls
//     back, so no recursion runs through one.
//   - Tail position. A call of a `tailcc` function from one is in tail
//     position when the path from it decides, by what it sees alone, to
//     return the call's result unchanged: through extractvalue and
//     insertvalue that take the result apart and put it back together,
//     through branches whose block arguments carry it, past conditions the
//     path decides (the exit flag a loop's tail passes as a constant) and
//     past ops that only compute. The call becomes `musttail`, with the
//     return moved right after it: LLVM then emits a tail call or fails to
//     compile, never silently a call.
//   - Results the target returns in memory. A result that does not fit the
//     return registers would come back through a hidden pointer into the
//     caller's frame, and LLVM makes no tail call of such a call. What fits
//     is the target's own answer: LLVM's lowering of `tailcc` is asked, for
//     the module's #llvm.target. Each function on a tail call whose result
//     does not fit takes a pointer to write its result to instead, first,
//     and returns nothing: a tail call passes on the pointer its caller got,
//     any other call a slot of its own frame, which it reads back.
//   - A frame's cells. A call that may reach its caller's frame through what
//     it takes (a cell idr-stack put there, or memory that holds one) stays
//     a call, since the frame has to outlive the callee. idr-stack puts on
//     the stack no cell that a call in tail position on its caller's cycle
//     takes, so such a call is never a recursion's: its callee, off the
//     cycle, never calls back round, and adds its frame once.

#include "Passes/Scc.h"
#include "idr/Idr.h"

#include "mlir/IR/PatternMatch.h"
#include "mlir/Target/LLVMIR/Transforms/TargetUtils.h"
#include "mlir/Target/LLVMIR/TypeToLLVM.h"
#include "mlir/Transforms/RegionUtils.h"

#include "llvm/CodeGen/MachineFunction.h"
#include "llvm/CodeGen/MachineModuleInfo.h"
#include "llvm/CodeGen/TargetLowering.h"
#include "llvm/CodeGen/TargetSubtargetInfo.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"
#include "llvm/Target/TargetMachine.h"
#include "llvm/TargetParser/Host.h"

#include <vector>

using namespace mlir;

namespace idr {
#define GEN_PASS_DEF_IDRTAILCALLS
#include "idr/Passes.h.inc"
} // namespace idr

namespace {

using LLVM::cconv::CConv;
using LLVM::tailcallkind::TailCallKind;

// What a value is on the path from a call to a return, as far as the path
// alone decides it: a part of the call's result (`path`, the positions an
// extractvalue takes, empty for the whole result), a constant, poison, a
// struct put together on the path, or unknown.
struct Known {
  enum class Kind : uint8_t { Unknown, Part, Constant, Poison, Struct };
  Kind kind = Kind::Unknown;
  SmallVector<int64_t, 2> path;
  Attribute constant;
  std::vector<Known> fields;

  static Known part(ArrayRef<int64_t> path) {
    Known k;
    k.kind = Kind::Part;
    k.path.assign(path.begin(), path.end());
    return k;
  }
  static Known of(Kind kind) {
    Known k;
    k.kind = kind;
    return k;
  }
};

unsigned fieldCount(Type type) {
  auto structure = dyn_cast<LLVM::LLVMStructType>(type);
  return structure ? static_cast<unsigned>(structure.getBody().size()) : 0;
}

// The part at `position` of a value known as `k`.
Known extract(const Known &k, ArrayRef<int64_t> position) {
  if (position.empty() || k.kind == Known::Kind::Poison)
    return k;
  if (k.kind == Known::Kind::Part) {
    SmallVector<int64_t, 4> path(k.path.begin(), k.path.end());
    llvm::append_range(path, position);
    return Known::part(path);
  }
  auto at = static_cast<size_t>(position.front());
  if (k.kind == Known::Kind::Struct && at < k.fields.size())
    return extract(k.fields[at], position.drop_front());
  return Known();
}

// A value known as `k`, of `type`, with the part at `position` replaced by
// `value`.
Known insert(const Known &k, Type type, ArrayRef<int64_t> position, const Known &value) {
  if (position.empty())
    return value;
  unsigned n = fieldCount(type);
  auto at = static_cast<size_t>(position.front());
  if (at >= n)
    return Known();
  Known out = Known::of(Known::Kind::Struct);
  for (unsigned i = 0; i < n; ++i) {
    SmallVector<int64_t, 1> index{static_cast<int64_t>(i)};
    out.fields.push_back(k.kind == Known::Kind::Struct ? k.fields[i]
                         : k.kind == Known::Kind::Unknown || k.kind == Known::Kind::Constant
                             ? Known()
                             : extract(k, index));
  }
  Type field = cast<LLVM::LLVMStructType>(type).getBody()[at];
  out.fields[at] = insert(out.fields[at], field, position.drop_front(), value);
  return out;
}

// Whether `k`, of `type`, is exactly the part of the call's result at `path`:
// that part, or a struct put together from each of its fields in order.
bool isPart(const Known &k, Type type, SmallVectorImpl<int64_t> &path) {
  if (k.kind == Known::Kind::Part)
    return ArrayRef(k.path) == ArrayRef(path);
  if (k.kind != Known::Kind::Struct || k.fields.size() != fieldCount(type))
    return false;
  auto structure = cast<LLVM::LLVMStructType>(type);
  for (auto [i, field] : llvm::enumerate(k.fields)) {
    path.push_back(static_cast<int64_t>(i));
    bool same = isPart(field, structure.getBody()[i], path);
    path.pop_back();
    if (!same)
      return false;
  }
  return true;
}

// Whether `call`, in `fn`, is in tail position: the path from it, which every
// op on it decides alone, returns the call's result unchanged, or returns
// nothing after a call that returns nothing. Every op on the way only
// computes, so returning right after the call loses nothing.
bool inTailPosition(LLVM::CallOp call, LLVM::LLVMFuncOp fn) {
  Type result = fn.getFunctionType().getReturnType();
  bool nothing = isa<LLVM::LLVMVoidType>(result);
  if (nothing != (call.getNumResults() == 0) ||
      (!nothing && call.getResult().getType() != result))
    return false;
  DenseMap<Value, Known> known;
  if (!nothing)
    known[call.getResult()] = Known::part({});
  auto lookup = [&](Value value) -> Known {
    if (auto it = known.find(value); it != known.end())
      return it->second;
    Operation *def = value.getDefiningOp();
    if (auto constant = dyn_cast_or_null<LLVM::ConstantOp>(def)) {
      Known k = Known::of(Known::Kind::Constant);
      k.constant = constant.getValue();
      return k;
    }
    if (isa_and_nonnull<LLVM::PoisonOp, LLVM::UndefOp>(def))
      return Known::of(Known::Kind::Poison);
    return Known();
  };
  // The path goes through each block once at most: one that comes round
  // again is a loop, and does not return the call's result.
  DenseSet<Block *> entered;
  Block::iterator at = std::next(call->getIterator());
  auto enter = [&](Block *block, ValueRange args) {
    if (!entered.insert(block).second)
      return false;
    SmallVector<Known> values = llvm::map_to_vector(args, lookup);
    for (auto [arg, value] : llvm::zip_equal(block->getArguments(), values))
      known[arg] = value;
    at = block->begin();
    return true;
  };
  // A decided condition: the constant `k` is an integer.
  auto decided = [](const Known &k) -> std::optional<APInt> {
    auto integer = k.kind == Known::Kind::Constant ? dyn_cast<IntegerAttr>(k.constant)
                                                   : IntegerAttr();
    if (!integer)
      return std::nullopt;
    return integer.getValue();
  };
  // Enough for the joins and loop exits of a lowered body, short of a scan
  // of a whole large function from every call in it.
  constexpr unsigned budget = 4096;
  for (unsigned steps = 0; steps < budget; ++steps) {
    Operation *op = &*at;
    if (auto ret = dyn_cast<LLVM::ReturnOp>(op)) {
      if (nothing)
        return true;
      SmallVector<int64_t, 4> path;
      return ret.getNumOperands() == 1 && isPart(lookup(ret.getOperand(0)), result, path);
    }
    if (auto branch = dyn_cast<LLVM::BrOp>(op)) {
      if (!enter(branch.getDest(), branch.getDestOperands()))
        return false;
      continue;
    }
    if (auto branch = dyn_cast<LLVM::CondBrOp>(op)) {
      std::optional<APInt> condition = decided(lookup(branch.getCondition()));
      if (!condition)
        return false;
      bool taken = !condition->isZero();
      if (!enter(taken ? branch.getTrueDest() : branch.getFalseDest(),
                 taken ? branch.getTrueDestOperands() : branch.getFalseDestOperands()))
        return false;
      continue;
    }
    if (auto branch = dyn_cast<LLVM::SwitchOp>(op)) {
      std::optional<APInt> value = decided(lookup(branch.getValue()));
      if (!value)
        return false;
      Block *dest = branch.getDefaultDestination();
      ValueRange operands = branch.getDefaultOperands();
      if (std::optional<DenseIntElementsAttr> cases = branch.getCaseValues())
        for (auto [i, key] : llvm::enumerate(cases->getValues<APInt>()))
          if (key == *value) {
            dest = branch.getCaseDestinations()[i];
            operands = branch.getCaseOperands(static_cast<unsigned>(i));
            break;
          }
      if (!enter(dest, operands))
        return false;
      continue;
    }
    if (op->hasTrait<OpTrait::IsTerminator>())
      return false;
    if (auto extract = dyn_cast<LLVM::ExtractValueOp>(op)) {
      known[extract.getResult()] = ::extract(lookup(extract.getContainer()), extract.getPosition());
    } else if (auto insert = dyn_cast<LLVM::InsertValueOp>(op)) {
      known[insert.getResult()] = ::insert(lookup(insert.getContainer()), insert.getType(),
                                           insert.getPosition(), lookup(insert.getValue()));
    } else if (op->getNumRegions() != 0 || !isMemoryEffectFree(op)) {
      return false;
    }
    ++at;
  }
  return false;
}

// What of a function may point into its frame: its slots (llvm.alloca, the
// cells idr-stack put there), what is computed from them, and what is read
// through them, since a slot may hold a pointer to another. A pointer into
// the frame may also have left it through memory, written somewhere that is
// not the frame: then any pointer a call takes may lead back to the frame.
// What a call does with a pointer it takes is idr-stack's to know: it puts on
// the stack only a cell that no callee keeps.
struct Frame {
  DenseSet<Value> bound;
  bool leaked = false;

  // Whether a value of `type` may hold a pointer: a pointer, or an
  // aggregate of anything that may (an array's view).
  static bool mayPoint(Type type) {
    if (isa<LLVM::LLVMPointerType>(type))
      return true;
    if (auto structure = dyn_cast<LLVM::LLVMStructType>(type))
      return llvm::any_of(structure.getBody(), mayPoint);
    if (auto array = dyn_cast<LLVM::LLVMArrayType>(type))
      return mayPoint(array.getElementType());
    return false;
  }

  explicit Frame(LLVM::LLVMFuncOp fn) {
    SmallVector<Value> work;
    auto add = [&](Value value) {
      if (value && bound.insert(value).second)
        work.push_back(value);
    };
    fn.walk([&](LLVM::AllocaOp slot) { add(slot.getResult()); });
    while (!work.empty()) {
      Value value = work.pop_back_val();
      for (OpOperand &use : value.getUses()) {
        Operation *user = use.getOwner();
        if (auto branch = dyn_cast<BranchOpInterface>(user)) {
          if (std::optional<BlockArgument> arg =
                  branch.getSuccessorBlockArgument(use.getOperandNumber()))
            add(*arg);
          continue;
        }
        if (auto load = dyn_cast<LLVM::LoadOp>(user)) {
          if (load.getAddr() == value && mayPoint(load.getType()))
            add(load.getResult());
          continue;
        }
        if (isa<LLVM::GEPOp, LLVM::AddrSpaceCastOp, LLVM::SelectOp, LLVM::InsertValueOp,
                LLVM::ExtractValueOp, LLVM::IntToPtrOp, LLVM::PtrToIntOp>(user))
          for (Value result : user->getResults())
            add(result);
      }
    }
    fn.walk([&](LLVM::StoreOp store) {
      leaked |= bound.contains(store.getValue()) && !bound.contains(store.getAddr());
    });
  }

  // Whether `call` may reach the frame through what it takes.
  bool reachedBy(LLVM::CallOp call) const {
    return leaked || llvm::any_of(call.getArgOperands(),
                                  [&](Value arg) { return bound.contains(arg); });
  }
};

// Whether a result of a `tailcc` function comes back in registers: what the
// target's lowering of calls decides (TargetLowering::CanLowerReturn), asked
// through the code generator's view of a function that returns the type, of
// a machine for the #llvm.target of the module or of the first module around
// it that has one, the program's. A module with none (a test's) is asked of
// this machine's triple and the generic CPU, which the JIT compiles it for.
class ReturnRegisters {
public:
  explicit ReturnRegisters(Operation *module) : scope(module) {}

  // None when there is no machine for the target.
  std::optional<bool> fit(Type type) {
    if (isa<LLVM::LLVMVoidType>(type))
      return true;
    if (auto it = answers.find(type); it != answers.end())
      return it->second;
    if (!machine && failed(prepare()))
      return std::nullopt;
    llvm::Type *translated = types->translateType(type);
    auto *fn = llvm::Function::Create(llvm::FunctionType::get(translated, false),
                                      llvm::GlobalValue::InternalLinkage, "probe", *probe);
    fn->setCallingConv(llvm::CallingConv::Tail);
    llvm::MachineFunction &mf = info->getOrCreateMachineFunction(*fn);
    const llvm::TargetLowering &lowering = *mf.getSubtarget().getTargetLowering();
    SmallVector<llvm::ISD::OutputArg, 8> outs;
    llvm::GetReturnInfo(llvm::CallingConv::Tail, translated, llvm::AttributeList(), outs, lowering,
                        probe->getDataLayout());
    bool fits =
        lowering.CanLowerReturn(llvm::CallingConv::Tail, mf, /*isVarArg=*/false, outs, context,
                                translated);
    info->deleteMachineFunctionFor(*fn);
    fn->eraseFromParent();
    answers[type] = fits;
    return fits;
  }

private:
  LogicalResult prepare() {
    MLIRContext *ctx = scope->getContext();
    LLVM::TargetAttr target;
    for (Operation *op = scope; op && !target; op = op->getParentOp())
      target = op->getAttrOfType<LLVM::TargetAttr>(LLVM::LLVMDialect::getTargetAttrName());
    if (!target)
      target = LLVM::TargetAttr::get(ctx, StringAttr::get(ctx, llvm::sys::getProcessTriple()),
                                     StringAttr::get(ctx, "generic"), LLVM::TargetFeaturesAttr());
    LLVM::detail::initializeBackendsOnce();
    machine = LLVM::detail::getTargetMachine(cast<LLVM::TargetAttrInterface>(target))
                  .value_or(nullptr);
    if (!machine) {
      scope->emitError("internal error: idr-tail-calls: no target machine for ")
          << target.getTriple();
      return failure();
    }
    probe = std::make_unique<llvm::Module>("idr-tail-calls", context);
    probe->setTargetTriple(machine->getTargetTriple());
    probe->setDataLayout(machine->createDataLayout());
    info = std::make_unique<llvm::MachineModuleInfo>(machine.get());
    types = std::make_unique<LLVM::TypeToLLVMIRTranslator>(context);
    return success();
  }

  Operation *scope;
  llvm::LLVMContext context;
  std::unique_ptr<llvm::TargetMachine> machine;
  std::unique_ptr<llvm::Module> probe;
  std::unique_ptr<llvm::MachineModuleInfo> info;
  std::unique_ptr<LLVM::TypeToLLVMIRTranslator> types;
  DenseMap<Type, bool> answers;
};

// A call of `callee`, of type `type`, with `operands`, in place of `call`:
// its calling convention and the attributes of its arguments, the first
// `inserted` arguments new and plain.
LLVM::CallOp recall(RewriterBase &rewriter, LLVM::CallOp call, LLVM::LLVMFunctionType type,
                    ValueRange operands, unsigned inserted) {
  auto fresh = LLVM::CallOp::create(rewriter, call.getLoc(), type, call.getCalleeAttr(), operands);
  fresh.setCConv(call.getCConv());
  fresh.setTailCallKind(call.getTailCallKind());
  if (ArrayAttr attrs = call.getArgAttrsAttr()) {
    SmallVector<Attribute> shifted(inserted, rewriter.getDictionaryAttr({}));
    llvm::append_range(shifted, attrs);
    fresh.setArgAttrsAttr(rewriter.getArrayAttr(shifted));
  }
  return fresh;
}

// The cycle of direct calls each function with a body is on: the index of
// its strongly connected component, which two functions share when each
// calls the other through any number of calls.
DenseMap<Operation *, unsigned> cyclesOf(ModuleOp module, SymbolTable &symbols) {
  SmallVector<Operation *> fns;
  for (auto fn : module.getOps<LLVM::LLVMFuncOp>())
    if (!fn.isExternal())
      fns.push_back(fn);
  auto callees = [&](Operation *fn) {
    SmallVector<Operation *> out;
    fn->walk([&](LLVM::CallOp call) {
      if (FlatSymbolRefAttr name = call.getCalleeAttr())
        if (Operation *callee = symbols.lookup(name.getAttr()))
          out.push_back(callee);
    });
    return out;
  };
  DenseMap<Operation *, unsigned> cycleOf;
  unsigned index = 0;
  for (const SmallVector<Operation *> &members :
       idr::passes::stronglyConnected<Operation *>(fns, callees)) {
    for (Operation *fn : members)
      cycleOf[fn] = index;
    ++index;
  }
  return cycleOf;
}

struct TailCalls : idr::impl::IdrTailCallsBase<TailCalls> {
  using IdrTailCallsBase::IdrTailCallsBase;

  void runOnOperation() override {
    ModuleOp module = getOperation();
    MLIRContext *ctx = &getContext();
    IRRewriter rewriter(ctx);

    // The functions only the module's calls reach.
    DenseSet<Operation *> internal;
    for (auto fn : module.getOps<LLVM::LLVMFuncOp>()) {
      if (fn.isExternal() || !fn.isPrivate() || fn.isVarArg())
        continue;
      std::optional<SymbolTable::UseRange> uses = SymbolTable::getSymbolUses(fn, module);
      if (!uses || llvm::any_of(*uses, [&](const SymbolTable::SymbolUse &use) {
            auto call = dyn_cast<LLVM::CallOp>(use.getUser());
            return !call || call.getCalleeAttr() != use.getSymbolRef();
          }))
        continue;
      internal.insert(fn);
    }
    SymbolTable symbols(module);
    auto calleeIn = [&](LLVM::CallOp call,
                        const DenseSet<Operation *> &among) -> LLVM::LLVMFuncOp {
      FlatSymbolRefAttr name = call.getCalleeAttr();
      auto callee = name ? symbols.lookup<LLVM::LLVMFuncOp>(name.getAttr()) : LLVM::LLVMFuncOp();
      return callee && among.contains(callee) ? callee : LLVM::LLVMFuncOp();
    };

    // The calls in tail position among them that leave the caller's frame
    // alone.
    SmallVector<LLVM::CallOp> candidates;
    for (auto fn : module.getOps<LLVM::LLVMFuncOp>()) {
      if (!internal.contains(fn))
        continue;
      std::optional<Frame> frame;
      fn.walk([&](LLVM::CallOp call) {
        if (!calleeIn(call, internal) || !inTailPosition(call, fn))
          return;
        if (!frame)
          frame.emplace(fn);
        if (frame->reachedBy(call)) {
          ++numFrameBound;
          return;
        }
        candidates.push_back(call);
      });
    }

    // The callers and callees of those on a cycle take tailcc, and so do
    // their calls; each call in tail position between two of them becomes
    // a tail call.
    DenseMap<Operation *, unsigned> cycleOf = cyclesOf(module, symbols);
    DenseSet<Operation *> tail;
    for (LLVM::CallOp call : candidates) {
      Operation *caller = call->getParentOfType<LLVM::LLVMFuncOp>();
      Operation *callee = calleeIn(call, internal);
      if (cycleOf.lookup(caller) == cycleOf.lookup(callee)) {
        tail.insert(caller);
        tail.insert(callee);
      }
    }
    for (Operation *op : tail)
      cast<LLVM::LLVMFuncOp>(op).setCConv(CConv::Tail);
    module.walk([&](LLVM::CallOp call) {
      if (calleeIn(call, tail))
        call.setCConv(CConv::Tail);
    });
    auto calleeOf = [&](LLVM::CallOp call) { return calleeIn(call, tail); };
    SmallVector<LLVM::CallOp> tails;
    for (LLVM::CallOp call : candidates)
      if (tail.contains(call->getParentOfType<LLVM::LLVMFuncOp>()) && calleeOf(call))
        tails.push_back(call);
    // The return right after each. What only the rest of a call's block led
    // to is unreachable then, and goes, with any call in tail position there.
    SetVector<Region *> split;
    for (LLVM::CallOp call : tails) {
      Block *block = call->getBlock();
      rewriter.splitBlock(block, std::next(call->getIterator()));
      rewriter.setInsertionPointToEnd(block);
      LLVM::ReturnOp::create(rewriter, call.getLoc(), call.getResults());
      split.insert(block->getParent());
    }
    DenseSet<Block *> reachable;
    for (Region *region : split) {
      SmallVector<Block *> work{&region->front()};
      while (!work.empty())
        if (Block *block = work.pop_back_val(); reachable.insert(block).second)
          llvm::append_range(work, block->getSuccessors());
    }
    llvm::erase_if(tails, [&](LLVM::CallOp call) {
      return split.contains(call->getParentRegion()) && !reachable.contains(call->getBlock());
    });
    for (Region *region : split)
      (void)eraseUnreachableBlocks(rewriter, *region);

    // The results that do not fit the return registers go through memory,
    // in every function on a tail call.
    SetVector<Operation *> onTails;
    for (LLVM::CallOp call : tails) {
      onTails.insert(call->getParentOfType<LLVM::LLVMFuncOp>());
      onTails.insert(calleeOf(call));
    }
    ReturnRegisters registers(module);
    SetVector<Operation *> inMemory;
    for (Operation *op : onTails) {
      auto fn = cast<LLVM::LLVMFuncOp>(op);
      std::optional<bool> fits = registers.fit(fn.getFunctionType().getReturnType());
      if (!fits)
        return signalPassFailure();
      if (!*fits)
        inMemory.insert(fn);
    }
    DenseSet<Operation *> tailCalls;
    for (LLVM::CallOp call : tails)
      tailCalls.insert(call);
    passThroughMemory(module, inMemory, tailCalls, rewriter);
    numInMemory += inMemory.size();

    module.walk([&](LLVM::CallOp call) {
      if (tailCalls.contains(call)) {
        call.setTailCallKind(TailCallKind::MustTail);
        ++numTailCalls;
      }
    });
  }

  // Each function of `inMemory` takes a pointer to write its result to, first,
  // and returns nothing. A call of one in `tailCalls`, right before the return
  // of its result, passes on the pointer its caller got (its caller returns the
  // same type, so it is in `inMemory` too); any other passes a slot of its
  // caller's frame and reads the result from it. `tailCalls` follows the calls
  // as they are made again.
  static void passThroughMemory(ModuleOp module, const SetVector<Operation *> &inMemory,
                                DenseSet<Operation *> &tailCalls, RewriterBase &rewriter) {
    if (inMemory.empty())
      return;
    MLIRContext *ctx = module.getContext();
    auto ptr = LLVM::LLVMPointerType::get(ctx);
    auto nothing = LLVM::LLVMVoidType::get(ctx);
    DenseMap<Operation *, Type> results;
    for (Operation *op : inMemory) {
      auto fn = cast<LLVM::LLVMFuncOp>(op);
      LLVM::LLVMFunctionType type = fn.getFunctionType();
      results[fn] = type.getReturnType();
      DictionaryAttr attrs = rewriter.getDictionaryAttr(
          rewriter.getNamedAttr(LLVM::LLVMDialect::getNoAliasAttrName(), rewriter.getUnitAttr()));
      (void)cast<FunctionOpInterface>(fn.getOperation()).insertArgument(0, ptr, attrs, fn.getLoc());
      fn.setFunctionType(
          LLVM::LLVMFunctionType::get(nothing, fn.getFunctionType().getParams(), false));
      fn.removeResAttrsAttr();
    }
    // Every call of such a function, in the new signature.
    SmallVector<LLVM::CallOp> calls;
    module.walk([&](LLVM::CallOp call) {
      FlatSymbolRefAttr name = call.getCalleeAttr();
      if (name && inMemory.contains(module.lookupSymbol(name.getAttr())))
        calls.push_back(call);
    });
    for (LLVM::CallOp call : calls) {
      auto callee = cast<LLVM::LLVMFuncOp>(module.lookupSymbol(call.getCalleeAttr().getAttr()));
      Type result = results.lookup(callee);
      auto caller = call->getParentOfType<LLVM::LLVMFuncOp>();
      SmallVector<Value> operands;
      if (tailCalls.contains(call)) {
        operands.push_back(caller.getArgument(0));
        llvm::append_range(operands, call.getArgOperands());
        rewriter.setInsertionPoint(call);
        LLVM::CallOp fresh = recall(rewriter, call, callee.getFunctionType(), operands, 1);
        Operation *ret = call->getNextNode();
        rewriter.setInsertionPoint(ret);
        LLVM::ReturnOp::create(rewriter, ret->getLoc(), ValueRange());
        rewriter.eraseOp(ret);
        rewriter.eraseOp(call);
        tailCalls.erase(call);
        tailCalls.insert(fresh);
        continue;
      }
      Block &entry = caller.getBody().front();
      rewriter.setInsertionPointToStart(&entry);
      Value one = LLVM::ConstantOp::create(rewriter, call.getLoc(), rewriter.getI64Type(),
                                           rewriter.getI64IntegerAttr(1));
      Value slot = LLVM::AllocaOp::create(rewriter, call.getLoc(), ptr, result, one, 0);
      operands.push_back(slot);
      llvm::append_range(operands, call.getArgOperands());
      rewriter.setInsertionPoint(call);
      recall(rewriter, call, callee.getFunctionType(), operands, 1);
      Value read = LLVM::LoadOp::create(rewriter, call.getLoc(), result, slot);
      rewriter.replaceOp(call, read);
    }
    // The other returns write the result.
    for (Operation *op : inMemory) {
      auto fn = cast<LLVM::LLVMFuncOp>(op);
      Value out = fn.getArgument(0);
      SmallVector<LLVM::ReturnOp> returns;
      fn.walk([&](LLVM::ReturnOp ret) { returns.push_back(ret); });
      for (LLVM::ReturnOp ret : returns) {
        if (ret.getNumOperands() == 0)
          continue;
        rewriter.setInsertionPoint(ret);
        LLVM::StoreOp::create(rewriter, ret.getLoc(), ret.getOperand(0), out);
        LLVM::ReturnOp::create(rewriter, ret.getLoc(), ValueRange());
        rewriter.eraseOp(ret);
      }
    }
  }
};

} // namespace
