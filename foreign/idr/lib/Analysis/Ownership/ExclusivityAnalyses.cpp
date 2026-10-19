// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The analyses of exclusivity's solve (Exclusivity.cpp says what it
// proves), on MLIR's solver beside upstream's dead-code analysis, which
// enters the program at its root from outside: the root is the one public
// function of the program, and a public callable's callers are unknown.
//   - NoConstants: reachability alone, every region can run.
//   - Running: which functions run. A function runs when a call that runs
//     goes to it, or when the program does not show every caller of it; a
//     call runs when its block may run and its function runs. A function no
//     call that runs goes to runs nowhere, so nothing it passes or returns
//     reaches any other, even where upstream's dead-code analysis keeps it
//     live through a call that goes elsewhere.
//   - ExclusiveAnalysis: the lattice of each value, from the reference
//     edges of each op, with calls going as Calls says. A call of a key of
//     grade specialization or of its copy runs the copy when every value it
//     passes at a followed parameter is exclusive, read off the same
//     lattice as it grows. A value only shares once it is shared, so a call
//     goes from the copy to the original at most once, and the solve ends
//     as any solve over a lattice of finite height does. A call that went to
//     the copy before an argument was found shared has given the copy only
//     exclusive values, and the copy what it returned then.
#include "idr/Analysis/Ownership/ExclusivityDetail.h"

#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Ownership.h"

#include "mlir/Analysis/DataFlow/ConstantPropagationAnalysis.h"
#include "mlir/Analysis/DataFlow/DeadCodeAnalysis.h"
#include "llvm/ADT/STLExtras.h"

#include <variant>

using namespace mlir;
using namespace mlir::dataflow;

namespace idr::detail::exclusivity {

void Cells::print(raw_ostream &os) const {
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

Calls::Calls(ProgramOp program, const ownership::Copies &copies) {
  for (FuncOp fn : program.getOps<FuncOp>()) {
    callees.try_emplace(fn.getSymNameAttr(), fn);
    // The body's one block ends in its return, or in ub.unreachable when
    // the function never returns.
    SmallVector<ReturnOp> &returns = returnsOf[fn];
    if (auto ret = dyn_cast<ReturnOp>(fn.getBody().front().getTerminator()))
      returns.push_back(ret);
  }
  for (auto [original, copy] : copies.of) {
    callees[original.getSymNameAttr()] = Pair{original, copy};
    callees[copy.getSymNameAttr()] = Pair{original, copy};
  }
}

const Calls::Callee &Calls::calleeOf(CallOp call) const {
  return callees.at(call.getCalleeAttr().getAttr());
}

SmallVector<FuncOp, 2> Calls::namesOf(FuncOp fn) const {
  return std::visit(
      llvm::makeVisitor([](FuncOp alone) { return SmallVector<FuncOp, 2>{alone}; },
                        [](Pair pair) { return SmallVector<FuncOp, 2>{pair.original, pair.copy}; }),
      callees.at(fn.getSymNameAttr()));
}

FuncOp Calls::target(CallOp call, function_ref<bool(Value)> isExclusive) const {
  return std::visit(
      llvm::makeVisitor([](FuncOp alone) { return alone; },
                        [&](Pair pair) {
                          for (auto [param, arg] : llvm::zip_equal(pair.original.getArguments(),
                                                                   call.getArgOperands()))
                            if (ownership::followed(param) && !isExclusive(arg))
                              return pair.original;
                          return pair.copy;
                        }),
      calleeOf(call));
}

namespace {

// Reachability alone. The dead-code analysis asks a constant lattice which
// region a branch takes, and which region a terminator leaves for, and a
// region only a constant would skip is the canonicalizer's to fold, not the
// solver's to leave ungraded: every value is a constant it does not know,
// so every region can run. That holds of a parameter and a call's result
// too, which the lattice would otherwise read off the calls the program
// names: a copy no call names yet runs when Running says it does, and what
// it returns is then reached all the same.
class NoConstants : public SparseForwardDataFlowAnalysis<Lattice<ConstantValue>> {
public:
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(NoConstants)
  using SparseForwardDataFlowAnalysis::SparseForwardDataFlowAnalysis;

  LogicalResult visitOperation(Operation *, ArrayRef<const Lattice<ConstantValue> *>,
                               ArrayRef<Lattice<ConstantValue> *> results) override {
    setAllToEntryStates(results);
    return success();
  }

  LogicalResult visitCallOperation(CallOpInterface, ArrayRef<const AbstractSparseLattice *>,
                                   ArrayRef<AbstractSparseLattice *> results) override {
    AbstractSparseForwardDataFlowAnalysis::setAllToEntryStates(results);
    return success();
  }

  void visitCallableOperation(CallableOpInterface,
                              ArrayRef<AbstractSparseLattice *> params) override {
    AbstractSparseForwardDataFlowAnalysis::setAllToEntryStates(params);
  }

  void setToEntryState(Lattice<ConstantValue> *lattice) override {
    propagateIfChanged(lattice, lattice->join(ConstantValue::getUnknownConstant()));
  }
};

// Which functions run. A function that runs has its body live, so
// upstream's dead-code analysis follows its blocks.
class Running : public DataFlowAnalysis {
public:
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(Running)

  Running(DataFlowSolver &solver, const Calls &calls) : DataFlowAnalysis(solver), calls(calls) {}

  LogicalResult initialize(Operation *top) override {
    for (FuncOp fn : cast<ProgramOp>(top).getOps<FuncOp>()) {
      visitFunction(fn);
      fn.walk([&](CallOp call) { visitCall(call); });
    }
    return success();
  }

  // The start of a function's body, when what is known of its callers
  // grew, or the point after a call, when its block, its function or what
  // it passes did.
  LogicalResult visit(ProgramPoint *point) override {
    if (point->isBlockStart()) {
      if (auto fn = dyn_cast<FuncOp>(point->getBlock()->getParentOp()))
        visitFunction(fn);
      return success();
    }
    if (auto call = dyn_cast<CallOp>(point->getPrevOp()))
      visitCall(call);
    return success();
  }

private:
  void visitFunction(FuncOp fn) {
    ProgramPoint *start = getProgramPointBefore(entryOf(fn));
    if (!getOrCreateFor<PredecessorState>(start, getProgramPointAfter(fn))->allPredecessorsKnown())
      run(fn);
  }

  void visitCall(CallOp call) {
    ProgramPoint *after = getProgramPointAfter(call);
    ProgramPoint *caller = getProgramPointBefore(entryOf(call->getParentOfType<FuncOp>()));
    if (!getOrCreateFor<Executable>(after, getProgramPointBefore(call->getBlock()))->isLive() ||
        !getOrCreateFor<Runs>(after, caller)->running())
      return;
    run(calls.target(call, [&](Value arg) {
      return exclusive(*getOrCreateFor<CellsLattice>(after, arg));
    }));
  }

  void run(FuncOp fn) {
    ProgramPoint *start = getProgramPointBefore(entryOf(fn));
    auto *runs = getOrCreate<Runs>(start);
    propagateIfChanged(runs, runs->setRunning());
    auto *live = getOrCreate<Executable>(start);
    propagateIfChanged(live, live->setToLive());
  }

  const Calls &calls;
};

class ExclusiveAnalysis : public SparseForwardDataFlowAnalysis<CellsLattice> {
public:
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(ExclusiveAnalysis)

  ExclusiveAnalysis(DataFlowSolver &solver, const Calls &calls)
      : SparseForwardDataFlowAnalysis(solver), calls(calls) {}

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
      // A flow into the result whole or into a part of it; a fresh result
      // is exclusive, a constant shared. A unification and a source are of
      // labels, and a use given up or a dispatch gives the result nothing.
      auto into = [&](const FlowEdges::Flow &move) {
        if (move.to.value() != result)
          return;
        if (std::holds_alternative<FlowPoint::Part>(move.to.at))
          parts = std::max(parts, intoPart(move.from, operands));
        else
          whole = std::max(whole, wholeFrom(move.from, operands));
      };
      for (const FlowEdges::Edge &edge : edges.edges())
        if (edge.carries(Carrier::Reference))
          std::visit(llvm::makeVisitor(into, [](const FlowEdges::Unify &) {},
                                       [](const FlowEdges::Source &) {},
                                       [&](const FlowEdges::Fresh &move) {
                                         if (move.to == result)
                                           whole = std::max(whole, Sharing::Exclusive);
                                       },
                                       [](const FlowEdges::Release &) {},
                                       [&](const FlowEdges::Constant &move) {
                                         if (move.to == result)
                                           whole = std::max(whole, Sharing::Shared);
                                       },
                                       [](const FlowEdges::Dispatch &) {}),
                     edge.move);
      Sharing sharing = whole == Sharing::Unknown ? Sharing::Shared : std::max(whole, parts);
      propagateIfChanged(lattice, lattice->join(Cells::of(sharing)));
    }
    return success();
  }

  // A value the program does not show every source of is shared.
  void setToEntryState(CellsLattice *lattice) override {
    propagateIfChanged(lattice, lattice->join(Cells::of(Sharing::Shared)));
  }

protected:
  // A call's results are what the returns of the function it runs give; a
  // call in a function that runs nowhere gives nothing. Every call of a
  // program in the owned stage is an idr.call.
  LogicalResult visitCallOperation(CallOpInterface callable,
                                   ArrayRef<const AbstractSparseLattice *>,
                                   ArrayRef<AbstractSparseLattice *> results) override {
    auto call = cast<CallOp>(callable.getOperation());
    ProgramPoint *after = getProgramPointAfter(call);
    ProgramPoint *caller = getProgramPointBefore(entryOf(call->getParentOfType<FuncOp>()));
    if (!getOrCreateFor<Runs>(after, caller)->running())
      return success();
    FuncOp target =
        calls.target(call, [&](Value arg) { return exclusive(*getLatticeElement(arg)); });
    for (ReturnOp ret : calls.returns(target))
      for (auto [value, result] : llvm::zip_equal(ret.getOperands(), results))
        join(result, *getLatticeElementFor(after, value));
    return success();
  }

  // A function's parameters are what the calls that run it pass, those of
  // either function of its pair that go to it, when the program shows every
  // call of it. Every callable of a program is an idr.func.
  void visitCallableOperation(CallableOpInterface callable,
                              ArrayRef<AbstractSparseLattice *> params) override {
    auto fn = cast<FuncOp>(callable.getOperation());
    ProgramPoint *start = getProgramPointBefore(entryOf(fn));
    for (FuncOp named : calls.namesOf(fn)) {
      const auto *sites = getOrCreateFor<PredecessorState>(start, getProgramPointAfter(named));
      if (!sites->allPredecessorsKnown())
        return AbstractSparseForwardDataFlowAnalysis::setAllToEntryStates(params);
      for (Operation *site : sites->getKnownPredecessors()) {
        auto call = cast<CallOp>(site);
        ProgramPoint *caller = getProgramPointBefore(entryOf(call->getParentOfType<FuncOp>()));
        if (!getOrCreateFor<Runs>(start, caller)->running() ||
            calls.target(call, [&](Value arg) {
              return exclusive(*getLatticeElementFor(start, arg));
            }) != fn)
          continue;
        for (auto [arg, param] : llvm::zip_equal(call.getArgOperands(), params))
          join(param, *getLatticeElementFor(start, arg));
      }
    }
  }

private:
  // What a flow from `from` brings a result it reaches whole: a use moved
  // into it, whole or out of a part, what that value holds; a copy of a
  // value read shares its cells, unless it is static data that reaches no
  // cell but atoms, which no take hands out; a part read, a parameter and a
  // result are shared.
  static Sharing wholeFrom(const FlowPoint &from, ArrayRef<const CellsLattice *> operands) {
    if (std::optional<OpOperand *> use = from.taken())
      return held(*operands[(*use)->getOperandNumber()]);
    const auto *read = std::get_if<FlowPoint::Whole>(&from.at);
    return read && ownership::reachesOnlyAtoms(read->value) ? Sharing::Exclusive
                                                             : Sharing::Shared;
  }

  // What a cell moved into a part of a result brings: a followed use what
  // it holds; anything else no cell a take could hand out.
  static Sharing intoPart(const FlowPoint &from, ArrayRef<const CellsLattice *> operands) {
    std::optional<OpOperand *> use = from.taken();
    if (!use)
      return Sharing::Shared;
    if (!ownership::followed((*use)->get()))
      return Sharing::Unknown;
    return held(*operands[(*use)->getOperandNumber()]);
  }

  static Sharing held(const CellsLattice &lattice) {
    return exclusive(lattice) ? Sharing::Exclusive : Sharing::Shared;
  }

  const Calls &calls;
};

} // namespace

void loadAnalyses(DataFlowSolver &solver, const Calls &calls) {
  solver.load<DeadCodeAnalysis>();
  solver.load<NoConstants>();
  solver.load<Running>(calls);
  solver.load<ExclusiveAnalysis>(calls);
}

} // namespace idr::detail::exclusivity
