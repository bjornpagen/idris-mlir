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

#include <ranges>

MLIR_DEFINE_EXPLICIT_TYPE_ID(idr::Ranges)

using namespace mlir;
using namespace mlir::dataflow;

namespace {

// The integers a literal match's keys are: a word's or a char's, and a
// big's or a natural's. A Double's and a string's keys are none, and their
// scrutinee's range, of no width, has no bound for one to cut.
SmallVector<APInt> integerKeys(idr::LitMatchOp match) {
  SmallVector<APInt> keys;
  for (Attribute key : match.getCases()) {
    if (auto word = dyn_cast<IntegerAttr>(key))
      keys.push_back(word.getValue());
    else if (auto big = dyn_cast<idr::BigAttr>(key))
      keys.push_back(big.getValue());
  }
  return keys;
}

class SummarizedRanges : public IntegerRangeAnalysis {
public:
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(SummarizedRanges)

  SummarizedRanges(DataFlowSolver &solver, idr::FuncOp fn,
                   std::span<const IntegerValueRange> arguments, const idr::Ranges &summaries)
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

  // A literal match's default binds its scrutinee, which it forwards, so
  // upstream would join the binding with the scrutinee's whole range and
  // never ask the op; but there the scrutinee is none of the keys, so the
  // binding takes the scrutinee's range with each key cut where it is an
  // end. The binding stays the scrutinee for every reader of forwarding.
  // The default's one predecessor is the match, and a block is visited
  // only once it is live. Every other region successor is upstream's.
  void visitRegionSuccessors(ProgramPoint *point, RegionBranchOpInterface branch,
                             RegionSuccessor successor,
                             ArrayRef<AbstractSparseLattice *> lattices) override {
    ++visits;
    auto match = dyn_cast<idr::LitMatchOp>(branch.getOperation());
    if (!match || successor.getSuccessor() != &match.getDefaultRegion())
      return AbstractSparseForwardDataFlowAnalysis::visitRegionSuccessors(point, branch, successor,
                                                                          lattices);
    Value scrutinee = match.getScrutinee();
    const IntegerValueRange &known = getLatticeElementFor(point, scrutinee)->getValue();
    if (known.isUninitialized())
      return;
    IntegerValueRange refined(
        idr::ranges::excluding(scrutinee.getType(), known.getValue(), integerKeys(match)));
    auto *binding = static_cast<IntegerValueRangeLattice *>(lattices.front());
    propagateIfChanged(binding, binding->join(refined));
  }

  // A call's results are what its callee returns, as summarized; a result
  // no return of the callee reached yet (a callee of the same component)
  // starts at its type's range.
  void visitExternalCall(CallOpInterface call, ArrayRef<const IntegerValueRangeLattice *>,
                         ArrayRef<IntegerValueRangeLattice *> results) override {
    ++visits;
    auto direct = cast<idr::CallOp>(call.getOperation());
    std::span<const IntegerValueRange> returned = summaries.returnsOf(direct.getCalleeAttr());
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
  std::span<const IntegerValueRange> arguments;
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
  idr::footprint::Vector<IntegerValueRange> arguments;
};

// A row of `n` ranges that nothing has reached.
auto unreached(unsigned n) {
  return std::views::iota(0u, n) |
         std::views::transform([](unsigned) { return IntegerValueRange(); });
}

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
                return unreached(fn ? fn.getNumResults() : 0);
              }),
      arguments(graph.size(), [&](solver::FunctionId f) {
        FuncOp fn = graph.op(f);
        return unreached(fn ? fn.getNumArguments() : 0);
      }) {
  MLIRContext &context = *program->getContext();

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
      std::span<IntegerValueRange> out = returns[f];
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
  IndexVector<solver::FunctionId, footprint::Vector<Passed>> passed(graph.size());
  solver::inSchedule<CallersFirst>(graph, context, [&](solver::SccId c) {
    bool feedsItself = graph.onCycle(c);
    for (solver::FunctionId f : graph.members(c)) {
      FuncOp fn = graph.op(f);
      std::span<IntegerValueRange> mine = arguments[f];
      if (feedsItself) {
        for (auto [summary, arg] : llvm::zip_equal(mine, fn.getArguments()))
          summary = IntegerValueRange::getMaxRange(arg);
        continue;
      }
      for (solver::FunctionId caller : graph.callers(f)) {
        const footprint::Vector<Passed> &theirs = passed[caller];
        auto it = llvm::partition_point(
            theirs, [&](const Passed &entry) { return entry.callee < f; });
        if (it == theirs.end() || it->callee != f)
          continue;
        for (auto [into, range] : llvm::zip_equal(mine, it->arguments))
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
      footprint::Vector<Passed> &mine = passed[f];
      fn.getBody().walk([&](CallOp call) {
        solver::FunctionId callee = graph.id(call.getCalleeAttr());
        if (graph.sccOf(callee) == c)
          return;
        auto it = llvm::partition_point(
            mine, [&](const Passed &entry) { return entry.callee < callee; });
        if (it == mine.end() || it->callee != callee)
          it = mine.insert(
              it, Passed{callee, footprint::Vector<IntegerValueRange>(call.getArgs().size())});
        for (auto [into, operand] : llvm::zip_equal(it->arguments, call.getArgs()))
          joinInto(into, passing(operand));
      });
    }
  });
}

} // namespace idr
