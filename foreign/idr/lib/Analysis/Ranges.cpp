// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The seeded range analysis, one function at a time: MLIR's integer range
// analysis with no interprocedural mode, starting a value it cannot see
// computed at the range its type proves, an entry argument at what its
// callers pass, a call's results at what its callee returns, and the
// program's poison as any value.
#include "idr/Analysis/Ranges.h"

#include "idr/Analysis/Solver/Extraction.h"
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
#include "llvm/ADT/Twine.h"
#include "llvm/Support/ErrorHandling.h"

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
  for (Attribute key : match.getCases())
    if (std::optional<APInt> integer = idr::keyInteger(key))
      keys.push_back(std::move(*integer));
  return keys;
}

// What a case of `key` binds of a scrutinee whose range is `known`: the
// key's value, where it is an integer the scrutinee's width holds; else
// all the scrutinee may be.
IntegerValueRange keyed(const IntegerValueRange &known, Attribute key) {
  unsigned width = known.getValue().smin().getBitWidth();
  std::optional<APInt> integer = idr::keyInteger(key);
  if (!integer || width == 0 || integer->getSignificantBits() > width)
    return known;
  return IntegerValueRange(ConstantIntRanges::constant(integer->sextOrTrunc(width)));
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

  // A literal match's every region binds its scrutinee, which it forwards,
  // so upstream would join each binding with the scrutinee's whole range
  // and never ask the op; but in a case the scrutinee is the case's key,
  // so a case's binding takes the key's value where the key is an integer
  // of the scrutinee's width, and in the default it is none of the keys, so
  // the default's binding takes the scrutinee's range with each key cut
  // where it is an end. A binding stays the scrutinee for every reader of
  // forwarding. A region's one predecessor is the match, and a block is
  // visited only once it is live. Every other region successor is
  // upstream's.
  void visitRegionSuccessors(ProgramPoint *point, RegionBranchOpInterface branch,
                             RegionSuccessor successor,
                             ArrayRef<AbstractSparseLattice *> lattices) override {
    ++visits;
    auto match = dyn_cast<idr::LitMatchOp>(branch.getOperation());
    if (!match || successor.isOperation())
      return AbstractSparseForwardDataFlowAnalysis::visitRegionSuccessors(point, branch, successor,
                                                                          lattices);
    Value scrutinee = match.getScrutinee();
    const IntegerValueRange &known = getLatticeElementFor(point, scrutinee)->getValue();
    if (known.isUninitialized())
      return;
    Region *entered = successor.getSuccessor();
    IntegerValueRange refined =
        entered == &match.getDefaultRegion()
            ? IntegerValueRange(idr::ranges::excluding(scrutinee.getType(), known.getValue(),
                                                       integerKeys(match)))
            : keyed(known, match.getCases()[match.caseOf(*entered)]);
    auto *binding = static_cast<IntegerValueRangeLattice *>(lattices.front());
    propagateIfChanged(binding, binding->join(refined));
  }

  // A call's results are what its callee returns, as summarized, wherever
  // the call stands; a result no return of the callee reached yet (a callee
  // of the same component) starts at its type's range.
  void visitExternalCall(CallOpInterface call, ArrayRef<const IntegerValueRangeLattice *>,
                         ArrayRef<IntegerValueRangeLattice *> results) override {
    ++visits;
    auto direct = cast<idr::FunctionCallOpInterface>(call.getOperation());
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

namespace {

// The bounds of `value` as `dataflow` found them: the program's poison,
// which may be taken to be any value, a small; none where the solve never
// reached it, which proves nothing; else its range cut to what its type
// proves, which holds wherever the solve lost it, as a natural's lower
// bound 0. A type that proves no range leaves the solve's as it is. The one
// read of a solve into a value's bounds.
ranges::Bounds boundsOf(const DataFlowSolver &dataflow, Value value) {
  if (value.getDefiningOp<ub::PoisonOp>())
    return {0, 0};
  std::optional<ConstantIntRanges> range = Ranges::rangeOf(dataflow, value);
  if (!range)
    return {};
  IntegerValueRange proved = ranges::ofType(value.getType());
  if (!proved.isUninitialized())
    range = range->intersection(proved.getValue());
  return ranges::boundsOf(*range);
}

// The bounds of every value of `fn`, read off `dataflow`, in the one walk
// order every reader numbers the function in.
footprint::Vector<ranges::Bounds> boundsOfEach(const DataFlowSolver &dataflow, FuncOp fn) {
  footprint::Vector<ranges::Bounds> row;
  solver::inWalkOrder(fn, [&](Value value) { row.push_back(boundsOf(dataflow, value)); });
  return row;
}

} // namespace

std::optional<ConstantIntRanges> Ranges::rangeOf(const DataFlowSolver &solver, Value value) {
  const auto *state = solver.lookupState<IntegerValueRangeLattice>(value);
  if (!state || state->getValue().isUninitialized())
    return std::nullopt;
  return state->getValue().getValue();
}

template <class Read>
  requires std::invocable<Read &, const mlir::DataFlowSolver &>
void Ranges::solve(FuncOp fn, solver::Work &work, Read &&read) const {
  DataFlowSolver dataflow(DataFlowConfig().setInterprocedural(false));
  // The integer range analysis is silent without dead code analysis, and
  // reads constants through constant propagation.
  loadBaselineAnalyses(dataflow);
  auto *ranges = dataflow.load<SummarizedRanges>(fn, arguments[graph.id(fn)], *this);
  LogicalResult ran = dataflow.initializeAndRun(fn);
  work.add(ranges->transfers());
  if (failed(ran))
    llvm::reportFatalInternalError(llvm::Twine("idr-narrow: MLIR's integer range solve of ") +
                                   fn.getSymName() + " failed");
  read(static_cast<const DataFlowSolver &>(dataflow));
}

footprint::Vector<ranges::Bounds> Ranges::boundsOfRewritten(FuncOp fn, solver::Work &work) const {
  footprint::Vector<ranges::Bounds> row;
  solve(fn, work, [&](const DataFlowSolver &dataflow) { row = boundsOfEach(dataflow, fn); });
  return row;
}

Ranges::Ranges(Operation *program, AnalysisManager &am)
    : graph(std::get<0>(reads(am))),
      returns(graph.size(),
              [&](solver::FunctionId f) {
                FuncOp fn = graph.op(f);
                return unreached(fn ? fn.getNumResults() : 0);
              }),
      arguments(graph.size(),
                [&](solver::FunctionId f) {
                  FuncOp fn = graph.op(f);
                  return unreached(fn ? fn.getNumArguments() : 0);
                }),
      bounded(graph.size()) {
  MLIRContext &context = *program->getContext();

  // What each function returns, callees first: the join over its returns
  // of what reaches them. A callee of the same component not yet solved
  // gives its type's range. A component's solves count into its own
  // count, which the schedule adds to the decide step's once every
  // component has run.
  solver::inSchedule<CalleesFirst>(graph, context, spent, [&](solver::SccId c) {
    solver::Work counted;
    for (solver::FunctionId f : graph.members(c)) {
      FuncOp fn = graph.op(f);
      solver::SolveUnit unit("idr-narrow returns", fn.getSymName());
      // A function returns through idr.return alone, whose parent is the
      // function; a yield ends a region of an op inside it.
      std::span<IntegerValueRange> out = returns[f];
      solve(fn, counted, [&](const DataFlowSolver &dataflow) {
        fn.getBody().walk([&](ReturnOp ret) {
          for (auto [into, operand] : llvm::zip_equal(out, ret->getOperands()))
            if (std::optional<ConstantIntRanges> range = rangeOf(dataflow, operand))
              joinInto(into, IntegerValueRange(*range));
        });
      });
    }
    return counted.steps();
  });

  // What each function is passed, callers first: the join over its callers
  // of what each passes it, read from the callers' finished components in
  // id order. A component that feeds itself starts every member at its
  // type's range. Each member's solve is then under its final summaries:
  // it keeps what it passes each callee of another component, in callee
  // order, for that callee's component, and the bounds of its values.
  IndexVector<solver::FunctionId, footprint::Vector<Passed>> passed(graph.size());
  solver::inSchedule<CallersFirst>(graph, context, spent, [&](solver::SccId c) {
    solver::Work counted;
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
      solve(fn, counted, [&](const DataFlowSolver &dataflow) {
        // What a call passes: what the solve found, nothing where the
        // solve never reached it.
        auto passing = [&](Value operand) -> IntegerValueRange {
          if (std::optional<ConstantIntRanges> range = rangeOf(dataflow, operand))
            return IntegerValueRange(*range);
          return IntegerValueRange();
        };
        footprint::Vector<Passed> &mine = passed[f];
        fn.getBody().walk([&](FunctionCallOpInterface call) {
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
        bounded[f] = boundsOfEach(dataflow, fn);
      });
    }
    return counted.steps();
  });
}

} // namespace idr
