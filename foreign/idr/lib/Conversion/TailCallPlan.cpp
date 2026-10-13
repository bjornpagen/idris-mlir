// The plan of idr-tail-calls, over the lowered module as it stands.

#include "idr/Conversion/Frame.h"
#include "idr/Conversion/ReturnRegisters.h"
#include "idr/Conversion/TailCallPlan.h"
#include "idr/Conversion/TailPosition.h"

#include "mlir/Analysis/CallGraph.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/IR/Threading.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/SCCIterator.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SetVector.h"

#include <optional>
#include <utility>

using namespace mlir;

namespace idr::conversion {

namespace {

using ByName = DenseMap<StringAttr, LLVM::LLVMFuncOp>;

// The callee of `call` among `among`, or null.
LLVM::LLVMFuncOp calleeIn(LLVM::CallOp call, const ByName &among) {
  FlatSymbolRefAttr name = call.getCalleeAttr();
  return name ? among.lookup(name.getAttr()) : LLVM::LLVMFuncOp();
}

// The calls in tail position of one internal function, found from its body
// alone: those that leave its frame alone, and how many do not.
struct Candidates {
  SmallVector<LLVM::CallOp> calls;
  uint64_t frameBound = 0;
};

// What of a function the entry reaches once a return follows each of its
// planned tail calls: the blocks, and in each the planned call after which
// the rest of the block, split off, is reached by nothing.
struct Reach {
  DenseSet<Block *> blocks;
  DenseMap<Block *, Operation *> cut;
};

Reach reach(LLVM::LLVMFuncOp fn, const DenseSet<Operation *> &planned) {
  Reach reached;
  SmallVector<Block *> work{&fn.getBody().front()};
  while (!work.empty()) {
    Block *block = work.pop_back_val();
    if (!reached.blocks.insert(block).second)
      continue;
    auto first = llvm::find_if(*block, [&](Operation &op) { return planned.contains(&op); });
    if (first != block->end()) {
      reached.cut[block] = &*first;
      continue;
    }
    llvm::append_range(work, block->getSuccessors());
  }
  return reached;
}

// Calls `each` with every call of `fn` that `reached` keeps, or with every
// call of it when nothing is split.
void forEachCallKept(LLVM::LLVMFuncOp fn, const Reach *reached,
                     function_ref<void(LLVM::CallOp)> each) {
  for (Block &block : fn.getBody()) {
    if (reached && !reached->blocks.contains(&block))
      continue;
    Operation *cut = reached ? reached->cut.lookup(&block) : nullptr;
    for (Operation &op : block) {
      op.walk([&](LLVM::CallOp call) { each(call); });
      if (&op == cut)
        break;
    }
  }
}

} // namespace

TailCallPlan::TailCallPlan(Operation *op, AnalysisManager &am) {
  auto module = cast<ModuleOp>(op);
  MLIRContext *ctx = module.getContext();

  // The functions only the module's calls reach.
  ByName internal;
  {
    SymbolTableCollection tables;
    SymbolUserMap users(tables, module);
    for (auto fn : module.getOps<LLVM::LLVMFuncOp>()) {
      if (fn.isExternal() || !fn.isPrivate() || fn.isVarArg())
        continue;
      StringAttr name = fn.getSymNameAttr();
      if (llvm::all_of(users.getUsers(fn), [&](Operation *user) {
            auto call = dyn_cast<LLVM::CallOp>(user);
            return call && call.getCalleeAttr() && call.getCalleeAttr().getAttr() == name;
          }))
        internal[name] = fn;
    }
  }

  // The calls in tail position among them that leave the caller's frame
  // alone, each function on its own.
  SmallVector<LLVM::LLVMFuncOp> callers;
  for (auto fn : module.getOps<LLVM::LLVMFuncOp>())
    if (internal.contains(fn.getSymNameAttr()))
      callers.push_back(fn);
  SmallVector<Candidates> found(callers.size());
  parallelFor(ctx, 0, callers.size(), [&](size_t i) {
    LLVM::LLVMFuncOp fn = callers[i];
    std::optional<Frame> frame;
    fn.walk([&](LLVM::CallOp call) {
      if (!calleeIn(call, internal) || !inTailPosition(call, fn))
        return;
      if (!frame)
        frame.emplace(fn);
      if (frame->reachedBy(call)) {
        ++found[i].frameBound;
        return;
      }
      found[i].calls.push_back(call);
    });
  });

  // The cycle of direct calls each function with a body is on.
  DenseMap<Operation *, unsigned> cycleOf;
  {
    const CallGraph &graph = am.getAnalysis<CallGraph>();
    unsigned index = 0;
    for (auto scc = llvm::scc_begin(&graph); !scc.isAtEnd(); ++scc, ++index)
      for (const CallGraphNode *node : *scc)
        if (!node->isExternal())
          cycleOf[node->getCallableRegion()->getParentOp()] = index;
  }

  // The callers and callees of candidates on a cycle take tailcc, and so do
  // their calls; each candidate between two of them is planned.
  ByName tail;
  for (auto [fn, candidates] : llvm::zip_equal(callers, found)) {
    bound += candidates.frameBound;
    for (LLVM::CallOp call : candidates.calls) {
      LLVM::LLVMFuncOp callee = calleeIn(call, internal);
      if (cycleOf.lookup(fn) == cycleOf.lookup(callee)) {
        tail[fn.getSymNameAttr()] = fn;
        tail[callee.getSymNameAttr()] = callee;
      }
    }
  }
  // The return right after each planned call leaves the rest of its block,
  // and what only that led to, unreached: a planned call there is dropped.
  DenseMap<Operation *, Reach> reached;
  llvm::SetVector<Operation *> onTails;
  for (auto [fn, candidates] : llvm::zip_equal(callers, found)) {
    if (!tail.contains(fn.getSymNameAttr()))
      continue;
    SmallVector<LLVM::CallOp> planned = llvm::to_vector(llvm::make_filter_range(
        candidates.calls, [&](LLVM::CallOp call) { return bool(calleeIn(call, tail)); }));
    if (planned.empty())
      continue;
    DenseSet<Operation *> plannedOps;
    for (LLVM::CallOp call : planned)
      plannedOps.insert(call);
    Reach &kept = reached[fn] = reach(fn, plannedOps);
    for (LLVM::CallOp call : planned) {
      if (!kept.blocks.contains(call->getBlock()) || kept.cut.lookup(call->getBlock()) != call)
        continue;
      functions[fn].tailCalls.push_back(call);
      onTails.insert(fn);
      onTails.insert(calleeIn(call, tail));
    }
  }

  // The results that do not fit the return registers go through memory, in
  // every function on a tail call. A function that takes the pointer
  // returns nothing.
  ReturnRegisters registers(module);
  DenseMap<Type, bool> fits;
  ByName inMemory;
  DenseMap<StringAttr, std::pair<Type, LLVM::LLVMFunctionType>> retyped;
  auto ptr = LLVM::LLVMPointerType::get(ctx);
  auto nothing = LLVM::LLVMVoidType::get(ctx);
  for (Operation *on : onTails) {
    auto fn = cast<LLVM::LLVMFuncOp>(on);
    LLVM::LLVMFunctionType type = fn.getFunctionType();
    auto [answer, fresh] = fits.try_emplace(type.getReturnType(), true);
    if (fresh) {
      std::optional<bool> fit = registers.fit(type.getReturnType());
      if (!fit) {
        machine = false;
        return;
      }
      answer->second = *fit;
    }
    if (answer->second)
      continue;
    inMemory[fn.getSymNameAttr()] = fn;
    functions[fn].inMemory = true;
    SmallVector<Type> params{ptr};
    llvm::append_range(params, type.getParams());
    retyped[fn.getSymNameAttr()] = {type.getReturnType(),
                                    LLVM::LLVMFunctionType::get(nothing, params, false)};
  }
  memory = inMemory.size();

  for (const auto &[name, fn] : tail)
    functions[fn].tail = true;
  for (auto fn : module.getOps<LLVM::LLVMFuncOp>()) {
    if (fn.isExternal())
      continue;
    fn.walk([&](LLVM::CallOp call) {
      if (calleeIn(call, tail))
        functions[fn].tailccCalls.push_back(call);
    });
    if (inMemory.empty())
      continue;
    auto it = reached.find(fn);
    forEachCallKept(fn, it == reached.end() ? nullptr : &it->second, [&](LLVM::CallOp call) {
      if (LLVM::LLVMFuncOp callee = calleeIn(call, inMemory)) {
        auto [result, type] = retyped.lookup(callee.getSymNameAttr());
        functions[fn].throughMemory.push_back({call, result, type});
      }
    });
  }
}

const TailCallPlan::Function *TailCallPlan::of(LLVM::LLVMFuncOp fn) const {
  auto it = functions.find(fn);
  return it == functions.end() ? nullptr : &it->second;
}

} // namespace idr::conversion
