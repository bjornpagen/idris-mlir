// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The seeded range analysis, one function at a time: MLIR's integer range
// analysis with no interprocedural mode, starting a value it cannot see
// computed at the range its type proves, an entry argument at what its
// callers pass, a call's results at what its callee returns, and the
// program's poison as any value.
#include "idr/Analysis/Ranges.h"

#include "idr/Analysis/Solver/Schedule.h"
#include "idr/Analysis/Solver/Trace.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Ranges.h"

#include "mlir/Analysis/DataFlow/IntegerRangeAnalysis.h"
#include "mlir/Analysis/DataFlow/Utils.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/Interfaces/CallInterfaces.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "mlir/Support/TypeID.h"
#include "llvm/ADT/STLExtras.h"

MLIR_DEFINE_EXPLICIT_TYPE_ID(idr::Ranges)

using namespace mlir;
using namespace mlir::dataflow;

namespace {

class SummarizedRanges : public IntegerRangeAnalysis {
public:
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(SummarizedRanges)

  SummarizedRanges(DataFlowSolver &solver, idr::FuncOp fn, const idr::RangeSummary &arguments,
                   const idr::Ranges &summaries)
      : IntegerRangeAnalysis(solver), fn(fn), arguments(arguments), summaries(summaries) {}

  // A value starts at the range its type proves, which for a natural is at
  // least 0, whatever its grade; an entry argument at what its callers
  // pass, where any caller was seen.
  void setToEntryState(IntegerValueRangeLattice *lattice) override {
    Value anchor = lattice->getAnchor();
    IntegerValueRange start = idr::ranges::ofType(anchor.getType());
    if (auto arg = dyn_cast<BlockArgument>(anchor);
        arg && arg.getOwner() == &fn.getBody().front() &&
        !arguments[arg.getArgNumber()].isUninitialized())
      start = arguments[arg.getArgNumber()];
    propagateIfChanged(lattice, lattice->join(start));
  }

  // A ub.poison is a value of the program, given where nothing reads it (as
  // idr-tail-loops passes it on the path that does not take it), and may be
  // any value: every range holds of it, so it adds nothing to the range of
  // a merge it flows into.
  LogicalResult visitOperation(Operation *op, ArrayRef<const IntegerValueRangeLattice *> operands,
                               ArrayRef<IntegerValueRangeLattice *> results) override {
    ++visits;
    if (isa<ub::PoisonOp>(op))
      return success();
    return IntegerRangeAnalysis::visitOperation(op, operands, results);
  }

  // A literal match's default binds the scrutinee itself: its argument has
  // the scrutinee's range, which the match forwards to no region as an
  // operand, so MLIR's analysis would start it at its type's range and lose
  // a natural's bound in every arm that takes a successor apart.
  void visitNonControlFlowArguments(Operation *op, const RegionSuccessor &successor,
                                    ValueRange inputs,
                                    ArrayRef<IntegerValueRangeLattice *> lattices) override {
    ++visits;
    auto match = dyn_cast<idr::LitMatchOp>(op);
    if (!match || successor.getSuccessor() != &match.getDefaultRegion() || inputs.size() != 1)
      return IntegerRangeAnalysis::visitNonControlFlowArguments(op, successor, inputs, lattices);
    const IntegerValueRangeLattice *scrutinee = getLatticeElementFor(
        getProgramPointBefore(&match.getDefaultRegion().front()), match.getScrutinee());
    propagateIfChanged(lattices.front(), lattices.front()->join(scrutinee->getValue()));
  }

  // A call's results are what its callee returns, as summarized; a result
  // no return of the callee reached yet (a callee of the same component)
  // starts at its type's range.
  void visitExternalCall(CallOpInterface call, ArrayRef<const IntegerValueRangeLattice *>,
                         ArrayRef<IntegerValueRangeLattice *> results) override {
    ++visits;
    auto direct = cast<idr::CallOp>(call.getOperation());
    const idr::RangeSummary &returned = summaries.returnsOf(direct.getCalleeAttr());
    for (auto [lattice, value] : llvm::zip_equal(results, returned)) {
      if (value.isUninitialized()) {
        setToEntryState(lattice);
        continue;
      }
      propagateIfChanged(lattice, lattice->join(value));
    }
  }

  // The transfers made: each op, call and region entry visited, each time.
  std::uint64_t transfers() const { return visits; }

private:
  idr::FuncOp fn;
  const idr::RangeSummary &arguments;
  const idr::Ranges &summaries;
  std::uint64_t visits = 0;
};

// Joins `range` into `into`.
void joinInto(IntegerValueRange &into, const IntegerValueRange &range) {
  into = IntegerValueRange::join(into, range);
}

// What one function passes one callee of another component: the join over
// its calls of that callee of each argument's range, uninitialized where
// no call was reached.
struct Passed {
  idr::solver::FunctionId callee;
  idr::RangeSummary arguments;
};

} // namespace

namespace idr {

Ranges::Solved::Solved() : dataflow(DataFlowConfig().setInterprocedural(false)) {}

std::optional<ConstantIntRanges> Ranges::rangeOf(const DataFlowSolver &solver, Value value) {
  const auto *state = solver.lookupState<IntegerValueRangeLattice>(value);
  if (!state || state->getValue().isUninitialized())
    return std::nullopt;
  return state->getValue().getValue();
}

FailureOr<std::unique_ptr<const Ranges::Solved>> Ranges::solve(FuncOp fn,
                                                               solver::Work &work) const {
  std::unique_ptr<Solved> solved(new Solved());
  // The integer range analysis is silent without dead code analysis, and
  // reads constants through constant propagation.
  loadBaselineAnalyses(solved->dataflow);
  auto *ranges = solved->dataflow.load<SummarizedRanges>(fn, arguments[graph.id(fn)], *this);
  LogicalResult ran = solved->dataflow.initializeAndRun(fn);
  work.add(ranges->transfers());
  if (failed(ran))
    return failure();
  return std::unique_ptr<const Solved>(std::move(solved));
}

Ranges::Ranges(Operation *program, AnalysisManager &am)
    : graph(std::get<0>(reads(am))),
      returns(graph.size(),
              [&](solver::FunctionId f) {
                FuncOp fn = graph.op(f);
                return fn ? RangeSummary(fn.getNumResults()) : RangeSummary();
              }),
      arguments(graph.size(), [&](solver::FunctionId f) {
        FuncOp fn = graph.op(f);
        return fn ? RangeSummary(fn.getNumArguments()) : RangeSummary();
      }) {
  MLIRContext &context = *program->getContext();
  auto cyclic = [&](solver::SccId c) {
    IdRange<solver::FunctionId> members = graph.members(c);
    return members.size() > 1 || graph.callsItself(members.front());
  };

  // What each function returns, callees first: the join over its returns
  // of what reaches them. A callee of the same component not yet solved
  // gives its type's range.
  solver::inSchedule<CalleesFirst>(graph, context, [&](solver::SccId c) {
    for (solver::FunctionId f : graph.members(c)) {
      FuncOp fn = graph.op(f);
      solver::SolveUnit unit("idr-narrow returns", fn.getSymName());
      FailureOr<std::unique_ptr<const Solved>> solved = solve(fn, spent);
      if (failed(solved))
        continue;
      RangeSummary &out = returns[f];
      fn.getBody().walk([&](Operation *op) {
        if (!op->hasTrait<OpTrait::ReturnLike>() || isa<RegionBranchTerminatorOpInterface>(op))
          return;
        for (auto [into, operand] : llvm::zip_equal(out, op->getOperands()))
          if (std::optional<ConstantIntRanges> range = (*solved)->rangeOf(operand))
            joinInto(into, IntegerValueRange(*range));
      });
    }
  });

  // What each function is passed, callers first: the join over its callers
  // of what each passes it, read from the callers' finished components in
  // id order. A component that feeds itself starts every member at its
  // type's range. Each member then keeps what it passes each callee of
  // another component, in callee order, for that callee's component.
  IndexVector<solver::FunctionId, std::vector<Passed>> passed(graph.size());
  solver::inSchedule<CallersFirst>(graph, context, [&](solver::SccId c) {
    bool feedsItself = cyclic(c);
    for (solver::FunctionId f : graph.members(c)) {
      FuncOp fn = graph.op(f);
      if (feedsItself) {
        for (auto [summary, arg] : llvm::zip_equal(arguments[f], fn.getArguments()))
          summary = IntegerValueRange::getMaxRange(arg);
        continue;
      }
      for (solver::FunctionId caller : graph.callers(f)) {
        const std::vector<Passed> &theirs = passed[caller];
        auto it = llvm::partition_point(
            theirs, [&](const Passed &entry) { return entry.callee < f; });
        if (it == theirs.end() || it->callee != f)
          continue;
        for (auto [into, range] : llvm::zip_equal(arguments[f], it->arguments))
          joinInto(into, range);
      }
    }
    for (solver::FunctionId f : graph.members(c)) {
      FuncOp fn = graph.op(f);
      solver::SolveUnit unit("idr-narrow arguments", fn.getSymName());
      FailureOr<std::unique_ptr<const Solved>> solved = solve(fn, spent);
      // What a call passes: what its solve found, nothing where the solve
      // never reached it; a caller whose solve failed knows nothing of what
      // it passes, so it passes every value the operand's type allows.
      auto passing = [&](Value operand) -> IntegerValueRange {
        if (failed(solved))
          return IntegerValueRange::getMaxRange(operand);
        if (std::optional<ConstantIntRanges> range = (*solved)->rangeOf(operand))
          return IntegerValueRange(*range);
        return IntegerValueRange();
      };
      std::vector<Passed> &mine = passed[f];
      fn.getBody().walk([&](CallOp call) {
        solver::FunctionId callee = graph.id(call.getCalleeAttr());
        if (graph.sccOf(callee) == c)
          return;
        auto it = llvm::partition_point(
            mine, [&](const Passed &entry) { return entry.callee < callee; });
        if (it == mine.end() || it->callee != callee)
          it = mine.insert(it, Passed{callee, RangeSummary(call.getArgs().size())});
        for (auto [into, operand] : llvm::zip_equal(it->arguments, call.getArgs()))
          joinInto(into, passing(operand));
      });
    }
  });
}

} // namespace idr
