// Exclusivity (Ownership/Ownership.h): which owned values hold the only
// reference to every cell of their cell graph, so that taking them apart
// needs no count test, and building in their cells no null test.
//
// In the owned stage a reference is duplicated only by idr.dup, so
// exclusivity is provenance: a value is exclusive when it is a constructor
// whose box fields are exclusive, a field an exclusive value was taken apart
// into (the token of that take too), a call's result that every return
// makes exclusive, or a parameter every caller passes exclusive. A dup, a
// constant (other than a nullary constructor, an atom no cell holds a
// count for), a stack cell and a value from a caller the module does not
// show are shared. The analysis is a sparse forward dataflow on MLIR's
// solver, optimistic as SCCP is: a value is exclusive until a path shares
// it, which is sound by induction on the run. What it proves is written
// into the types (`!idr.excl<T>`), which every later pass keeps and the
// owned stage's verifier checks.

#include "Ownership/Ownership.h"

#include "mlir/Analysis/DataFlow/ConstantPropagationAnalysis.h"
#include "mlir/Analysis/DataFlow/DeadCodeAnalysis.h"
#include "mlir/Analysis/DataFlow/SparseAnalysis.h"
#include "mlir/Analysis/DataFlowFramework.h"
#include "mlir/IR/Matchers.h"

#include "llvm/ADT/SetVector.h"
#include "llvm/Support/Debug.h"

#define DEBUG_TYPE "idr-rc"

using namespace mlir;
using namespace mlir::dataflow;

namespace idr::ownership {

namespace {

// The values whose cell graph the analysis follows: owned boxes and
// unboxed sums (whose slots may hold boxes), and the tokens of their cells.
bool followed(Value value) {
  Type type = value.getType();
  return isOwned(type) && isa<BoxType, DataType, TokenType>(unrestricted(type));
}

// What is known of a value's cell graph: nothing yet (the optimistic
// start), a tree of cells this value alone reaches, or cells another
// reference may reach.
enum class Sharing : uint8_t { Unknown, Exclusive, Shared };

struct Cells {
  Sharing sharing = Sharing::Unknown;

  static Cells of(Sharing sharing) { return {sharing}; }

  static Cells join(const Cells &a, const Cells &b) {
    return of(std::max(a.sharing, b.sharing));
  }

  bool operator==(const Cells &) const = default;

  void print(raw_ostream &os) const {
    switch (sharing) {
    case Sharing::Unknown:
      os << "unknown";
      return;
    case Sharing::Exclusive:
      os << "exclusive";
      return;
    case Sharing::Shared:
      os << "shared";
      return;
    }
  }
};

struct CellsLattice : Lattice<Cells> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(CellsLattice)
  using Lattice::Lattice;
};

// Reachability alone. The dead-code analysis asks a constant lattice which
// region a branch takes, and a region only a constant would skip is the
// canonicalizer's to fold, not the solver's to leave ungraded: every value
// is a constant it does not know, so every region can run.
class NoConstants : public SparseForwardDataFlowAnalysis<Lattice<ConstantValue>> {
public:
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(NoConstants)
  using SparseForwardDataFlowAnalysis::SparseForwardDataFlowAnalysis;

  LogicalResult visitOperation(Operation *, ArrayRef<const Lattice<ConstantValue> *>,
                               ArrayRef<Lattice<ConstantValue> *> results) override {
    for (Lattice<ConstantValue> *lattice : results)
      setToEntryState(lattice);
    return success();
  }

  void setToEntryState(Lattice<ConstantValue> *lattice) override {
    propagateIfChanged(lattice, lattice->join(ConstantValue::getUnknownConstant()));
  }
};

} // namespace

bool isAtom(Value view) {
  ConAttr con;
  return matchPattern(view, m_Constant(&con)) && con.getFields().empty();
}

namespace {

// The owned value a view was read from: through views (idr.borrow), fields
// (idr.field, the fields a match's region binds) and changes of quantity.
Value viewRoot(Value value) {
  for (;;) {
    if (auto arg = dyn_cast<BlockArgument>(value)) {
      auto match = dyn_cast<MatchOp>(arg.getOwner()->getParentOp());
      if (!match)
        return value;
      value = match.getScrutinee();
      continue;
    }
    Operation *def = value.getDefiningOp();
    if (isa_and_nonnull<BorrowOp, FieldOp, LinEnterOp, LinUseOp>(def)) {
      value = def->getOperand(0);
      continue;
    }
    return value;
  }
}

class ExclusiveAnalysis : public SparseForwardDataFlowAnalysis<CellsLattice> {
public:
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(ExclusiveAnalysis)
  using SparseForwardDataFlowAnalysis::SparseForwardDataFlowAnalysis;

  LogicalResult visitOperation(Operation *op, ArrayRef<const CellsLattice *> operands,
                               ArrayRef<CellsLattice *> results) override {
    // A constructor reaches its box fields' cells; a stack cell is lent
    // to whoever holds it, never theirs.
    if (isa<ConOp, ReuseOp>(op)) {
      Sharing sharing = op->hasAttr("idr.stack") ? Sharing::Shared : Sharing::Exclusive;
      for (auto [operand, lattice] : llvm::zip(op->getOperands(), operands))
        if (followed(operand) && !isa<TokenType>(unrestricted(operand.getType())))
          sharing = std::max(sharing, held(lattice));
      return set(results[0], sharing);
    }
    if (auto dup = dyn_cast<DupOp>(op))
      return set(results[0], isAtom(dup.getValue()) ? Sharing::Exclusive : Sharing::Shared);
    // The fields of an exclusive value are exclusive: it alone reached
    // them. So is the cell it leaves behind.
    if (isa<TakeOp>(op)) {
      Sharing sharing = held(operands[0]);
      for (auto [result, lattice] : llvm::zip(op->getResults(), results))
        if (followed(result))
          propagateIfChanged(lattice, lattice->join(Cells::of(sharing)));
      return success();
    }
    if (isa<LinEnterOp, LinUseOp>(op))
      return set(results[0], held(operands[0]));
    if (isa<ShareOp>(op))
      return set(results[0], Sharing::Shared);
    // Poison is no value: nothing reaches its cells.
    if (isa<ub::PoisonOp>(op))
      return set(results[0], Sharing::Exclusive);
    for (auto [result, lattice] : llvm::zip(op->getResults(), results))
      if (followed(result))
        propagateIfChanged(lattice, lattice->join(Cells::of(Sharing::Shared)));
    return success();
  }

  // A value the module does not show every source of is shared.
  void setToEntryState(CellsLattice *lattice) override {
    propagateIfChanged(lattice, lattice->join(Cells::of(Sharing::Shared)));
  }

private:
  // What an operand holds, optimistically: unknown counts as exclusive
  // until a path shares it.
  static Sharing held(const CellsLattice *lattice) {
    return lattice->getValue().sharing == Sharing::Shared ? Sharing::Shared : Sharing::Exclusive;
  }

  LogicalResult set(CellsLattice *lattice, Sharing sharing) {
    propagateIfChanged(lattice, lattice->join(Cells::of(sharing)));
    return success();
  }
};

// Before the solver: a value some view of which takes a reference of its
// own (idr.dup, here or in a callee that borrows the value) has shared
// cells by the time it is consumed, whatever it alone reached when it was
// made. Its consuming use gets it shared (idr.share): the solver reads the
// shared value there, and the value itself keeps what its provenance
// proves, which its callee's or constructor's type must agree with.
void shareTainted(ModuleOp module) {
  SymbolTableCollection symbols;
  llvm::SetVector<Value> tainted;
  llvm::DenseMap<Operation *, SmallVector<unsigned>> borrowedRoots;
  module.walk([&](DupOp dup) {
    Value root = viewRoot(dup.getValue());
    if (followed(root))
      tainted.insert(root);
    auto arg = dyn_cast<BlockArgument>(root);
    auto fn = arg ? dyn_cast<func::FuncOp>(arg.getOwner()->getParentOp()) : func::FuncOp();
    if (fn && !isOwned(arg.getType()))
      borrowedRoots[fn].push_back(arg.getArgNumber());
  });
  module.walk([&](func::CallOp call) {
    func::FuncOp fn = callee(call, symbols);
    auto it = fn ? borrowedRoots.find(fn) : borrowedRoots.end();
    if (it == borrowedRoots.end())
      return;
    for (unsigned index : it->second)
      if (Value root = viewRoot(call.getArgOperands()[index]); followed(root))
        tainted.insert(root);
  });
  OpBuilder b(module.getContext());
  for (Value value : tainted)
    for (OpOperand &use : llvm::make_early_inc_range(value.getUses()))
      if (useOf(use, symbols) == Use::Consume) {
        b.setInsertionPoint(use.getOwner());
        use.set(ShareOp::create(b, use.getOwner()->getLoc(), value.getType(), value));
      }
}

// The commit: the values the solver proved exclusive get the grade, and
// where an exclusive value meets a position typed owned (a call's argument,
// a return, a yield), it is shared into it.
class Commit {
public:
  Commit(ModuleOp module, DataFlowSolver &solver) : module(module), solver(solver) {}

  FailureOr<unsigned> run() {
    unsigned exclusive = 0;
    // A call's results join the callee's returns the solver reached, which
    // it records after the call: the callee's results are those returns'.
    SymbolTableCollection symbols;
    llvm::DenseMap<Operation *, func::CallOp> callOf;
    module.walk([&](func::CallOp call) {
      if (func::FuncOp fn = callee(call, symbols))
        callOf.try_emplace(fn, call);
    });
    for (auto fn : module.getOps<func::FuncOp>()) {
      if (fn.isExternal())
        continue;
      // A value before its uses: what follows its operand's type reads
      // the operand already marked.
      fn.walk<WalkOrder::PreOrder>([&](Block *block) {
        for (BlockArgument arg : block->getArguments())
          exclusive += mark(arg);
        for (Operation &op : *block)
          for (Value result : op.getResults())
            exclusive += mark(result);
      });
      SmallVector<Type> results(fn.getResultTypes());
      auto call = callOf.lookup(fn);
      auto *returns =
          call ? solver.lookupState<PredecessorState>(solver.getProgramPointAfter(call)) : nullptr;
      if (returns && returns->allPredecessorsKnown() && !returns->getKnownPredecessors().empty()) {
        for (auto [index, type] : llvm::enumerate(results)) {
          if (!isOwned(type))
            continue;
          bool all = llvm::all_of(returns->getKnownPredecessors(), [&](Operation *ret) {
            return isExclusive(ret->getOperand(static_cast<unsigned>(index)).getType());
          });
          if (all)
            type = graded({gradeOf(type).quantity, Permission::Excl}, unrestricted(type));
        }
      }
      fn.setFunctionType(FunctionType::get(module.getContext(),
                                           llvm::to_vector(fn.getBody().getArgumentTypes()), results));
    }
    // A call's results are its callee's: on a path the solver never
    // reached, a call has no lattice of its own.
    module.walk([&](func::CallOp call) {
      if (func::FuncOp fn = callee(call, symbols))
        for (auto [result, type] : llvm::zip(call.getResults(), fn.getResultTypes()))
          result.setType(type);
    });
    // Every position now says what it takes.
    OpBuilder b(module.getContext());
    WalkResult walked = module.walk([&](Operation *op) -> WalkResult {
      if (auto call = dyn_cast<func::CallOp>(op)) {
        if (func::FuncOp fn = callee(call, symbols))
          for (auto [operand, expected] : llvm::zip(call.getArgOperandsMutable(), fn.getArgumentTypes()))
            if (failed(meet(b, operand, expected)))
              return WalkResult::interrupt();
      } else if (auto ret = dyn_cast<func::ReturnOp>(op)) {
        auto fn = ret->getParentOfType<func::FuncOp>();
        for (auto [operand, expected] : llvm::zip(ret->getOpOperands(), fn.getResultTypes()))
          if (failed(meet(b, operand, expected)))
            return WalkResult::interrupt();
      } else if (auto yield = dyn_cast<YieldOp>(op)) {
        for (auto [operand, expected] :
             llvm::zip(yield->getOpOperands(), yield->getParentOp()->getResultTypes()))
          if (failed(meet(b, operand, expected)))
            return WalkResult::interrupt();
      }
      return WalkResult::advance();
    });
    if (walked.wasInterrupted())
      return failure();
    // A share of a value that is not exclusive shares nothing.
    module.walk([&](ShareOp share) {
      if (isExclusive(share.getValue().getType()))
        return;
      share.getResult().replaceAllUsesWith(share.getValue());
      share.erase();
    });
    return exclusive;
  }

private:
  // A value whose type its own op derives from its operand's (a change of
  // quantity, a share) follows the operand: a linear value of an exclusive
  // one is exclusive.
  bool live(Block *block) {
    auto *state = solver.lookupState<Executable>(solver.getProgramPointBefore(block));
    return state && state->isLive();
  }

  unsigned mark(Value value) {
    if (!followed(value))
      return 0;
    Operation *def = value.getDefiningOp();
    if (isa_and_nonnull<ShareOp>(def))
      return 0;
    if (isa_and_nonnull<LinEnterOp, LinUseOp>(def)) {
      Type type = atQuantity(def->getOperand(0).getType(), quantityOf(value.getType()));
      bool changed = type != value.getType();
      value.setType(type);
      return changed ? 1 : 0;
    }
    auto *lattice = solver.lookupState<CellsLattice>(value);
    if (!lattice || lattice->getValue().sharing != Sharing::Exclusive)
      return 0;
    value.setType(graded({gradeOf(value.getType()).quantity, Permission::Excl},
                         unrestricted(value.getType())));
    return 1;
  }

  // `operand` where `expected` is taken: an exclusive value is shared into
  // an owned position. An owned one in an exclusive position is on a path
  // the solver never reached (whose values it never graded), where it is
  // poison; anywhere else it is the solver and the commit disagreeing,
  // which is a bug here, never a program to compile.
  LogicalResult meet(OpBuilder &b, OpOperand &operand, Type expected) {
    Type type = operand.get().getType();
    if (type == expected || !isOwned(expected))
      return success();
    Operation *op = operand.getOwner();
    b.setInsertionPoint(op);
    if (isExclusive(type) && !isExclusive(expected)) {
      operand.set(ShareOp::create(b, op->getLoc(), expected, operand.get()));
      return success();
    }
    if (!isExclusive(type) && isExclusive(expected)) {
      auto *live = solver.lookupState<Executable>(solver.getProgramPointBefore(op->getBlock()));
      if (live && live->isLive())
        return op->emitOpError("idr-rc: gives a value of ")
               << type << " where the solver proved " << expected;
      operand.set(ub::PoisonOp::create(b, op->getLoc(), expected));
    }
    return success();
  }

  ModuleOp module;
  DataFlowSolver &solver;
};

} // namespace

namespace {

// A function called with exclusive values from some callers and shared ones
// from others would take its parameters shared, and test every cell for
// all of them. Instead it is specialized on the grade, as the specializer
// specializes on types: the calls whose every followed argument is
// exclusive go to a copy of their own, whose parameters the next solve
// proves exclusive. A call is redirected at most once, so the rounds end.
// A function whose callers the solver does not all see (a closure's code)
// keeps them, and a copy is never copied again.
class Specialize {
public:
  // The copies made so far, by their original, which a call made exclusive
  // by an earlier round's copy joins.
  using Copies = llvm::DenseMap<Operation *, func::FuncOp>;

  Specialize(ModuleOp module, DataFlowSolver &solver, Copies &copies)
      : module(module), solver(solver), copies(copies) {}

  bool run() {
    SymbolTableCollection symbols;
    SmallVector<func::FuncOp> fns(module.getOps<func::FuncOp>());
    bool redirected = false;
    for (func::FuncOp fn : fns) {
      if (fn.isExternal() || fn.isPublic() || fn.getSymName().ends_with(copySuffix))
        continue;
      auto *callers = solver.lookupState<PredecessorState>(solver.getProgramPointAfter(fn));
      if (!callers || !callers->allPredecessorsKnown())
        continue;
      SmallVector<func::CallOp> exclusiveCalls;
      bool mixed = false;
      for (Operation *pred : callers->getKnownPredecessors()) {
        auto call = dyn_cast<func::CallOp>(pred);
        if (!call || !isLive(call))
          continue;
        if (improves(fn, call))
          exclusiveCalls.push_back(call);
        else
          mixed = true;
      }
      if (exclusiveCalls.empty() || !mixed)
        continue;
      func::FuncOp copy = copyOf(fn);
      for (func::CallOp call : exclusiveCalls)
        call.setCalleeAttr(FlatSymbolRefAttr::get(copy.getSymNameAttr()));
      LLVM_DEBUG(llvm::dbgs() << "idr-rc: " << exclusiveCalls.size() << " calls of @"
                              << fn.getSymName() << " go to @" << copy.getSymName() << "\n");
      redirected = true;
    }
    return redirected;
  }

private:
  static constexpr StringLiteral copySuffix = "$excl";

  bool isLive(Operation *op) {
    auto *state = solver.lookupState<Executable>(solver.getProgramPointBefore(op->getBlock()));
    return state && state->isLive();
  }

  Sharing sharingOf(Value value) {
    auto *lattice = solver.lookupState<CellsLattice>(value);
    return lattice ? lattice->getValue().sharing : Sharing::Unknown;
  }

  // Whether the call gives every followed parameter an exclusive value, and
  // at least one of them a value the function now takes shared.
  bool improves(func::FuncOp fn, func::CallOp call) {
    bool gains = false;
    for (auto [param, arg] : llvm::zip(fn.getArguments(), call.getArgOperands())) {
      if (!followed(param))
        continue;
      if (sharingOf(arg) != Sharing::Exclusive)
        return false;
      gains |= sharingOf(param) == Sharing::Shared;
    }
    return gains;
  }

  func::FuncOp copyOf(func::FuncOp fn) {
    auto it = copies.find(fn);
    if (it != copies.end())
      return it->second;
    func::FuncOp copy = fn.clone();
    copy.setSymName((fn.getSymName() + copySuffix).str());
    copy.setPrivate();
    OpBuilder b(fn);
    b.setInsertionPointAfter(fn);
    b.insert(copy.getOperation());
    copies.try_emplace(fn, copy);
    return copy;
  }

  ModuleOp module;
  DataFlowSolver &solver;
  Copies &copies;
};

} // namespace

FailureOr<unsigned> inferExclusive(ModuleOp module) {
  // A clone names itself (idr.clone) without calling it, which the solver
  // would take for a caller it cannot see; nothing after idr-rc reads it.
  for (auto fn : module.getOps<func::FuncOp>())
    fn->removeAttr("idr.clone");
  shareTainted(module);
  Specialize::Copies copies;
  // Every round redirects a call for good, so the rounds are bounded by
  // the calls; a round past that is a bug here.
  unsigned calls = 0;
  module.walk([&](func::CallOp) { ++calls; });
  for (unsigned round = 0;; ++round) {
    DataFlowSolver solver(DataFlowConfig().setInterprocedural(true));
    solver.load<DeadCodeAnalysis>();
    solver.load<NoConstants>();
    solver.load<ExclusiveAnalysis>();
    if (failed(solver.initializeAndRun(module)))
      return failure();
    if (round <= calls && Specialize(module, solver, copies).run())
      continue;
    if (round > calls)
      return module.emitError("idr-rc: specializing on exclusivity did not settle"), failure();
    FailureOr<unsigned> exclusive = Commit(module, solver).run();
    if (failed(exclusive))
      return failure();
    // A function every call of which went to its copy is unused.
    for (auto [original, copy] : copies)
      if (SymbolTable::symbolKnownUseEmpty(original, module))
        original->erase();
    return exclusive;
  }
}

} // namespace idr::ownership
