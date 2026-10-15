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
// exclusivity is provenance, read from the reference edges of each op
// (idr/IR/Flow.h): a value is exclusive when its op makes it new and every
// cell moved into a part of it is exclusive (a constructor of exclusive
// fields), when a use of an exclusive value moves into it whole or out of
// one of its parts (a change of quantity; a field an exclusive value was
// taken apart into, and the token of that take), when it is a call's
// result that every return makes exclusive or a parameter every caller
// passes exclusive, or when it is a copy of static data built only of
// atoms. So the pair of empty lists that span and splitAt give at the end
// of their input joins the pair they build around an exclusive one, and
// the join stays exclusive. Any other copy, a constant, a stack cell (the
// frame's, so not new to anyone), a value no flow explains (a share's,
// which forgets what its operand alone reached) and a value from a caller
// the program does not show are shared, and so is every result of an op
// that declares no flow. The analysis is a sparse forward dataflow on
// MLIR's solver, optimistic as SCCP is: a value is exclusive until a path
// shares it, which is sound by induction on the run. It reads the dups
// placement made, so it runs after placement; what it proves idr-rc writes
// into the types (`!idr.excl<T>`), which every later pass keeps and the
// owned stage's verifier checks.
//
// The solver answers by program point and value, which the passes after
// it ask of the function they rewrite; so its answers are copied into
// tables and the solver is gone when the constructor returns.
#include "idr/Analysis/Ownership.h"

#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Ownership.h"

#include "mlir/Analysis/DataFlow/ConstantPropagationAnalysis.h"
#include "mlir/Analysis/DataFlow/DeadCodeAnalysis.h"
#include "mlir/Analysis/DataFlow/SparseAnalysis.h"
#include "mlir/Analysis/DataFlowFramework.h"

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

// The program is entered at its root, from outside: its callers are not
// the program's to show. Every other function is private, entered only by
// the calls the program makes.
class Entry : public DataFlowAnalysis {
public:
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(Entry)

  Entry(DataFlowSolver &solver, FuncOp root) : DataFlowAnalysis(solver), root(root) {}

  LogicalResult initialize(Operation *) override {
    auto *callers = getOrCreate<PredecessorState>(getProgramPointAfter(root));
    propagateIfChanged(callers, callers->setHasUnknownPredecessors());
    return success();
  }
  LogicalResult visit(ProgramPoint *) override { return success(); }

private:
  FuncOp root;
};

class ExclusiveAnalysis : public SparseForwardDataFlowAnalysis<CellsLattice> {
public:
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(ExclusiveAnalysis)

  using SparseForwardDataFlowAnalysis::SparseForwardDataFlowAnalysis;

  // Each followed result is what reaches it whole (new, a use of a value
  // moved into it or out of a part of one, a copy, a constant), joined with
  // the cells moved into its parts; a result nothing reaches whole is not
  // new to anyone, and shared.
  LogicalResult visitOperation(Operation *op, ArrayRef<const CellsLattice *> operands,
                               ArrayRef<CellsLattice *> results) override {
    FlowEdges edges;
    if (declaresFlow(op))
      flowEdgesOf(op, edges);
    for (auto [result, lattice] : llvm::zip(op->getResults(), results)) {
      if (!ownership::followed(result))
        continue;
      Sharing whole = Sharing::Unknown, parts = Sharing::Unknown;
      for (const FlowEdges::Edge &edge : edges.edges()) {
        if (!edge.carries(Carrier::Reference) || edge.to.getValue() != result)
          continue;
        if (edge.to.kind == FlowPoint::Kind::Part) {
          parts = std::max(parts, intoPart(edge.from, operands));
          continue;
        }
        whole = std::max(whole, reaching(edge, operands));
      }
      Sharing sharing = whole == Sharing::Unknown ? Sharing::Shared : std::max(whole, parts);
      propagateIfChanged(lattice, lattice->join(Cells::of(sharing)));
    }
    return success();
  }

  // A value the program does not show every source of is shared.
  void setToEntryState(CellsLattice *lattice) override {
    propagateIfChanged(lattice, lattice->join(Cells::of(Sharing::Shared)));
  }

private:
  // What an operand holds, optimistically: unknown counts as exclusive
  // until a path shares it.
  static Sharing held(const CellsLattice *lattice) {
    return lattice->getValue().sharing == Sharing::Shared ? Sharing::Shared : Sharing::Exclusive;
  }

  // What reaches a result whole along `edge`: a new value is exclusive; a
  // use moved into it, whole or out of a part, brings what that value
  // holds; a copy of a value read shares its cells, unless it is static
  // data that reaches no cell but atoms, which no take hands out; a part
  // read and a constant are shared.
  static Sharing reaching(const FlowEdges::Edge &edge, ArrayRef<const CellsLattice *> operands) {
    using Kind = FlowEdges::Edge::Kind;
    if (edge.kind == Kind::Fresh)
      return Sharing::Exclusive;
    if (edge.kind != Kind::Flow)
      return Sharing::Shared;
    const FlowPoint &from = edge.from;
    if (from.takes())
      return held(operands[from.operand->getOperandNumber()]);
    if (from.kind == FlowPoint::Kind::Value && ownership::reachesOnlyAtoms(from.value))
      return Sharing::Exclusive;
    return Sharing::Shared;
  }

  // What a cell moved into a part of a result brings: a followed use what
  // it holds; anything else no cell a take could hand out.
  static Sharing intoPart(const FlowPoint &from, ArrayRef<const CellsLattice *> operands) {
    if (!from.takes())
      return Sharing::Shared;
    if (!ownership::followed(from.operand->get()))
      return Sharing::Unknown;
    return held(operands[from.operand->getOperandNumber()]);
  }
};

} // namespace

Exclusivity::Exclusivity(Operation *op, AnalysisManager &) {
  auto program = cast<ProgramOp>(op);
  DataFlowSolver solver(DataFlowConfig().setInterprocedural(true));
  solver.load<Entry>(program.lookupRoot());
  solver.load<DeadCodeAnalysis>();
  solver.load<NoConstants>();
  solver.load<ExclusiveAnalysis>();
  if (mlir::failed(solver.initializeAndRun(program))) {
    unsolved = true;
    return;
  }
  auto record = [&](Value value) {
    if (auto *lattice = solver.lookupState<CellsLattice>(value);
        lattice && lattice->getValue().sharing != Sharing::Unknown)
      sharing[value] = lattice->getValue().sharing;
  };
  program->walk([&](Block *block) {
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
  program.walk([&](CallOp call) { callOf.try_emplace(call.getCalleeAttr().getAttr(), call); });
  for (FuncOp fn : program.getOps<FuncOp>()) {
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

// A value its op moves one of its uses into whole, at the use's carrier
// (a change of quantity), is that use's value, and is proved as that is,
// solved or made after the solve. A share's value is reached whole by
// nothing, so the solve found it shared.
bool Exclusivity::proves(Value value) const {
  if (!ownership::followed(value))
    return false;
  if (auto flow = dyn_cast_or_null<FlowOpInterface>(value.getDefiningOp())) {
    FlowEdges edges;
    flow.getFlowEdges(edges);
    for (const FlowEdges::Edge &edge : edges.edges())
      if (edge.kind == FlowEdges::Edge::Kind::Flow && edge.carries(Carrier::Reference) &&
          edge.from.kind == FlowPoint::Kind::Operand && edge.to.kind == FlowPoint::Kind::Value &&
          edge.to.value == value &&
          unrestricted(edge.from.operand->get().getType()) == unrestricted(value.getType()))
        return proves(edge.from.operand->get());
  }
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
