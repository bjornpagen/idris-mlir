// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Exclusivity: which owned values hold the only reference to every cell
// of their cell graph that a take could hand out, so that taking them
// apart needs no count test, and building in their cells no null test.
// Those are the cells with fields; static data built only of atoms has
// none to hand out (an atom has no fields to take, an unboxed sum no
// cell), no count reaches it and nothing frees or writes it, so it is in
// every exclusive tree however many hold it (reachesOnlyAtoms).
//
// In the owned stage a reference is duplicated only by idr.dup, so
// exclusivity is provenance: a value is exclusive when it is a constructor
// whose box fields are exclusive, a field an exclusive value was taken
// apart into (the token of that take too), a call's result that every
// return makes exclusive, a parameter every caller passes exclusive, or a
// copy of static data built only of atoms. So the pair of empty lists that
// span and splitAt give at the end of their input joins the pair they
// build around an exclusive one, and the join stays exclusive. Any other
// dup or constant, a stack cell and a value from a caller the module does
// not show are shared. The analysis is a sparse forward dataflow on MLIR's
// solver, optimistic as SCCP is: a value is exclusive until a path shares
// it, which is sound by induction on the run. It reads the dups placement
// made, so it runs after placement; what it proves idr-rc writes into the
// types (`!idr.excl<T>`), which every later pass keeps and the owned
// stage's verifier checks.
//
// The solver answers by program point and value, which the passes after
// it ask of the function they rewrite; so its answers are copied into
// tables and the solver is gone when the constructor returns.
#include "idr/Analysis/Ownership.h"

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Ownership.h"
#include "idr/IR/Symbols.h"

#include "mlir/Analysis/DataFlow/ConstantPropagationAnalysis.h"
#include "mlir/Analysis/DataFlow/DeadCodeAnalysis.h"
#include "mlir/Analysis/DataFlow/SparseAnalysis.h"
#include "mlir/Analysis/DataFlowFramework.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/BuiltinOps.h"

using namespace mlir;
using namespace mlir::dataflow;
using Sharing = idr::Exclusivity::Sharing;

namespace idr {

namespace {

// What is known of a value's cell graph, as the lattice holds it.
struct Cells {
  Sharing sharing = Sharing::Unknown;

  static Cells of(Sharing sharing) { return {sharing}; }

  static Cells join(const Cells &a, const Cells &b) { return of(std::max(a.sharing, b.sharing)); }

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

class ExclusiveAnalysis : public SparseForwardDataFlowAnalysis<CellsLattice> {
public:
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(ExclusiveAnalysis)

  ExclusiveAnalysis(DataFlowSolver &solver, SymbolTable &symbols)
      : SparseForwardDataFlowAnalysis(solver), symbols(symbols),
        stack(symbols.getOp()->getContext()) {}

  LogicalResult visitOperation(Operation *op, ArrayRef<const CellsLattice *> operands,
                               ArrayRef<CellsLattice *> results) override {
    // A constructor reaches its box fields' cells; a stack cell is lent
    // to whoever holds it, never theirs.
    if (isa<ConOp, ReuseOp>(op)) {
      Sharing sharing = stack.isAttrPresent(op) ? Sharing::Shared : Sharing::Exclusive;
      for (auto [operand, lattice] : llvm::zip(op->getOperands(), operands))
        if (ownership::followed(operand) && !isa<TokenType>(unrestricted(operand.getType())))
          sharing = std::max(sharing, held(lattice));
      return set(results[0], sharing);
    }
    // A copy of static data that reaches no cell but atoms is in every
    // exclusive tree; any other copy shares its cells with the original.
    if (auto dup = dyn_cast<DupOp>(op)) {
      bool atoms = ownership::reachesOnlyAtoms(
          dup.getValue(), [&](Type type) { return lookupData(symbols, type); });
      return set(results[0], atoms ? Sharing::Exclusive : Sharing::Shared);
    }
    // The fields of an exclusive value are exclusive: it alone reached
    // them. So is the cell it leaves behind.
    if (isa<TakeOp>(op)) {
      Sharing sharing = held(operands[0]);
      for (auto [result, lattice] : llvm::zip(op->getResults(), results))
        if (ownership::followed(result))
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
      if (ownership::followed(result))
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

  SymbolTable &symbols;
  IdrDialect::StackAttrHelper stack;
};

} // namespace

Exclusivity::Exclusivity(Operation *op, AnalysisManager &am) {
  auto module = cast<ModuleOp>(op);
  SymbolTable &symbols = am.getAnalysis<SymbolTable>();
  DataFlowSolver solver(DataFlowConfig().setInterprocedural(true));
  solver.load<DeadCodeAnalysis>();
  solver.load<NoConstants>();
  solver.load<ExclusiveAnalysis>(symbols);
  if (mlir::failed(solver.initializeAndRun(module))) {
    unsolved = true;
    return;
  }
  auto record = [&](Value value) {
    if (auto *lattice = solver.lookupState<CellsLattice>(value);
        lattice && lattice->getValue().sharing != Sharing::Unknown)
      sharing[value] = lattice->getValue().sharing;
  };
  module->walk([&](Block *block) {
    if (auto *state = solver.lookupState<Executable>(solver.getProgramPointBefore(block));
        state && state->isLive())
      liveBlocks.insert(block);
    for (BlockArgument arg : block->getArguments())
      record(arg);
    for (Operation &inner : *block)
      for (Value result : inner.getResults())
        record(result);
  });
  // A call's results join the callee's returns the solver reached, which
  // it records after the call; any one call of a function shows them.
  DenseMap<StringAttr, CallOp> callOf;
  module.walk([&](CallOp call) { callOf.try_emplace(call.getCalleeAttr().getAttr(), call); });
  for (FuncOp fn : module.getOps<FuncOp>()) {
    if (auto *preds = solver.lookupState<PredecessorState>(solver.getProgramPointAfter(fn));
        preds && preds->allPredecessorsKnown())
      callersOf[fn].assign(preds->getKnownPredecessors().begin(),
                           preds->getKnownPredecessors().end());
    CallOp call = callOf.lookup(fn.getSymNameAttr());
    if (!call)
      continue;
    if (auto *preds = solver.lookupState<PredecessorState>(solver.getProgramPointAfter(call));
        preds && preds->allPredecessorsKnown())
      returnsOf[fn].assign(preds->getKnownPredecessors().begin(),
                           preds->getKnownPredecessors().end());
  }
}

bool Exclusivity::isInvalidated(const AnalysisManager::PreservedAnalyses &pa) const {
  return !pa.isPreserved<Exclusivity>() || !pa.isPreserved<SymbolTable>();
}

Sharing Exclusivity::of(Value value) const {
  auto it = sharing.find(value);
  return it == sharing.end() ? Sharing::Unknown : it->second;
}

// A value whose type its own op derives from its operand's (a change of
// quantity) follows the operand: a linear value of an exclusive one is
// exclusive. A share forgets what its operand alone reached.
bool Exclusivity::proves(Value value) const {
  if (!ownership::followed(value))
    return false;
  Operation *def = value.getDefiningOp();
  if (isa_and_nonnull<ShareOp>(def))
    return false;
  if (isa_and_nonnull<LinEnterOp, LinUseOp>(def))
    return proves(def->getOperand(0));
  return of(value) == Sharing::Exclusive;
}

std::optional<ArrayRef<Operation *>> Exclusivity::callers(FuncOp fn) const {
  auto it = callersOf.find(fn);
  if (it == callersOf.end())
    return std::nullopt;
  return ArrayRef<Operation *>(it->second);
}

std::optional<ArrayRef<Operation *>> Exclusivity::returns(FuncOp fn) const {
  auto it = returnsOf.find(fn);
  if (it == returnsOf.end())
    return std::nullopt;
  return ArrayRef<Operation *>(it->second);
}

} // namespace idr
