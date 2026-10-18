// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The copy of a vectorized loop in a scratch module, where the bound on its
// sizes is tried and its integer ops narrowed. The copy's inputs are its
// function's arguments, so the analysis sees no bound on them but the
// stand-ins', and each trial solves one loop, not its whole function.

#include "idr/Transforms/Narrow.h"

#include "mlir/Analysis/DataFlow/IntegerRangeAnalysis.h"
#include "mlir/Analysis/DataFlow/Utils.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Arith/Transforms/Passes.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/IRMapping.h"
#include "mlir/IR/Matchers.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"

#include "llvm/ADT/STLExtras.h"

using namespace mlir;
using namespace mlir::dataflow;

namespace idr::narrow {

Copy Copy::of(Location loc, scf::ForOp loop, const SetVector<Value> &inputs) {
  MLIRContext *ctx = loc.getContext();
  OwningOpRef<ModuleOp> module = ModuleOp::create(loc);
  SmallVector<Value> arguments;
  for (Value input : inputs)
    if (!matchPattern(input, m_Constant()))
      arguments.push_back(input);
  auto function = func::FuncOp::create(
      loc, "copy", FunctionType::get(ctx, ValueRange(arguments).getTypes(), {}));
  module->push_back(function);
  Block *entry = function.addEntryBlock();
  OpBuilder b = OpBuilder::atBlockEnd(entry);
  IRMapping into;
  llvm::MapVector<Type, Value> bounds;
  for (Value input : inputs)
    if (matchPattern(input, m_Constant()))
      into.map(input, b.clone(*input.getDefiningOp())->getResult(0));
  for (auto [input, arg] : llvm::zip_equal(arguments, entry->getArguments())) {
    Value standIn = arg;
    if (testable(input)) {
      Value &bound = bounds[input.getType()];
      if (!bound)
        bound = arith::ConstantOp::create(b, loc, IntegerAttr::get(input.getType(), 0));
      standIn = arith::MinUIOp::create(b, loc, arg, bound);
    }
    into.map(input, standIn);
  }
  auto copy = cast<scf::ForOp>(b.clone(*loop, into));
  func::ReturnOp::create(b, loc);
  return Copy(std::move(module), function, copy, std::move(arguments), std::move(bounds));
}

void Copy::bound(unsigned exponent) {
  for (auto [type, constant] : bounds)
    cast<arith::ConstantOp>(constant.getDefiningOp())
        .setValueAttr(IntegerAttr::get(type, int64_t{1} << exponent));
}

FailureOr<std::unique_ptr<DataFlowSolver>> Copy::analyse(unsigned exponent) {
  bound(exponent);
  // After lowering there is no natural to seed: upstream's analysis, within
  // the copy's one function.
  auto solver = std::make_unique<DataFlowSolver>(DataFlowConfig().setInterprocedural(false));
  loadBaselineAnalyses(*solver);
  solver->load<IntegerRangeAnalysis>();
  if (failed(solver->initializeAndRun(*module)))
    return failure();
  return solver;
}

// The stand-ins before the copied loop read the inputs, which fit nothing.
// Whether an op's 32-bit form computes the same is the narrowing's to
// decide: it leaves wide an op whose 32-bit form would compute something
// else, and an accumulation, which fits under no bound. An op that computes
// on no integer wider than 32 bits (laneWidth) is not asked, a select among
// them: it moves lanes, and costs the same at any width. The set of ops
// tried does not depend on the bound, so a smaller bound still fits
// whatever a larger one does.
bool Copy::fits(DataFlowSolver &solver) {
  auto fit = [&](Value value) {
    if (ConstantIntRanges::getStorageBitwidth(value.getType()) == 0)
      return true;
    std::optional<ConstantIntRanges> range = Ranges::rangeOf(solver, value);
    return range && fits32(*range);
  };
  llvm::DenseSet<Operation *> carried = accumulations(copy);
  return !copy
              ->walk([&](Operation *op) {
                if (laneWidth(op).bits <= 32 || carried.contains(op) ||
                    (llvm::all_of(op->getOperands(), fit) && llvm::all_of(op->getResults(), fit)))
                  return WalkResult::advance();
                return WalkResult::interrupt();
              })
              .wasInterrupted();
}

// Upstream's narrowing patterns under upstream's driver, configured as its
// own passes configure it: users first (its int-range-narrowing's
// bottom-up traversal), so that a comparison still finds the ranges of its
// operands, which are the values analysed; the solver told of every op the
// driver erases; and no folding and no region simplification (its
// int-range-optimizations), which can erase a block argument without a
// word to the solver, so that a new one at its address would take its
// range. The driver folds the index cast chains the narrowing leaves (the
// set holds that pattern) and erases what no one reads. It stops at
// upstream's default iteration budget, and its result is not read: a
// budget spent leaves the copy less narrowed, its other lanes wide, never
// wrong.
void Copy::narrow(DataFlowSolver &solver) {
  struct Listener : RewriterBase::Listener {
    explicit Listener(DataFlowSolver &s) : solver(s) {}
    void notifyOperationErased(Operation *op) override {
      solver.eraseState(solver.getProgramPointAfter(op));
      for (Value result : op->getResults())
        solver.eraseState(result);
    }
    DataFlowSolver &solver;
  } listener(solver);
  RewritePatternSet patterns(module->getContext());
  arith::populateIntRangeNarrowingPatterns(patterns, solver, {32});
  (void)applyPatternsGreedily(function, std::move(patterns),
                              GreedyRewriteConfig()
                                  .setUseTopDownTraversal(false)
                                  .enableFolding(false)
                                  .setRegionSimplificationLevel(GreedySimplifyRegionLevel::Disabled)
                                  .setListener(&listener));

  // The narrowing widens a result back with arith.extui, and knows the word
  // it widens is non-negative (its range, kept on the cast); the flag says
  // so where LLVM reads it, so that the conversion to double of such a word
  // is the signed one (uitofp nneg, after the canonicalization of sitofp of
  // it), which the target has for 32-bit lanes where it has no unsigned
  // one.
  SmallVector<arith::ExtUIOp> nonNegative;
  function.walk([&](arith::ExtUIOp widen) {
    std::optional<ConstantIntRanges> range = Ranges::rangeOf(solver, widen.getResult());
    if (range && range->smin().isNonNegative() && fits32(*range))
      nonNegative.push_back(widen);
  });
  for (arith::ExtUIOp widen : nonNegative)
    widen.setNonNeg(true);
}

void Copy::cloneInto(OpBuilder &b) {
  Block &entry = function.getBody().front();
  IRMapping back;
  back.map(entry.getArguments(), arguments);
  for (Operation &op : entry.without_terminator())
    b.clone(op, back);
}

} // namespace idr::narrow
