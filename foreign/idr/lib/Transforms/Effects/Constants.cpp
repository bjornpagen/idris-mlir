// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-constants: sparse conditional constant propagation through one
// function, as upstream's solver and analyses do it, with a call's results
// taken from what its callee returns once the callee's component of the
// ready set is final. It is the last step of idr-optimize's inner
// pipeline, so that a function's final body states its own summary: every
// value the solve holds constant is a constant op when the step ends, a
// return's operands among them, and the ready set reads the summary from
// there when the component finishes.
//
// The summaries are idr-optimize's, cached on the module for the length of
// its run, and read here through the parent; a function never reads
// another function's body.
#include "idr/Transforms/Effects.h"

#include "idr/Analysis/Constants.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/Analysis/DataFlow/DeadCodeAnalysis.h"
#include "mlir/Analysis/DataFlowFramework.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/Matchers.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "mlir/Transforms/FoldUtils.h"
#include "llvm/ADT/STLExtras.h"

namespace idr {
#define GEN_PASS_DEF_IDRCONSTANTS
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;
using mlir::dataflow::ConstantValue;
using mlir::dataflow::Lattice;

namespace {

// Gives every use of `value` the constant the solve holds for it, made by
// `folder` in the dialect that folded it, at `builder`'s block; whether it
// could. A value the solve never reached, or found to vary, keeps its uses.
bool replaceWithConstant(DataFlowSolver &solver, OperationFolder &folder, OpBuilder &builder,
                         Value value) {
  const auto *lattice = solver.lookupState<Lattice<ConstantValue>>(value);
  if (!lattice || lattice->getValue().isUninitialized())
    return false;
  Attribute constant = lattice->getValue().getConstantValue();
  if (!constant)
    return false;
  Value made = folder.getOrCreateConstant(builder.getInsertionBlock(),
                                          lattice->getValue().getConstantDialect(), constant,
                                          value.getType());
  if (!made)
    return false;
  value.replaceAllUsesWith(made);
  return true;
}

// The rewrite of the solve over the body of `fn`, blocks before the regions
// they hold, so that a constant met first is the one the folder hands out
// for its value. An op every result of which became a constant goes when
// nothing else keeps it, its regions with it. How many values it replaced.
unsigned rewrite(DataFlowSolver &solver, idr::FuncOp fn) {
  OperationFolder folder(fn.getContext());
  OpBuilder builder(fn.getContext());
  unsigned replaced = 0;
  SmallVector<Block *> blocks;
  auto enqueue = [&](MutableArrayRef<Region> regions) {
    for (Region &region : regions)
      for (Block &block : llvm::reverse(region))
        blocks.push_back(&block);
  };
  enqueue(fn->getRegions());
  while (!blocks.empty()) {
    Block *block = blocks.pop_back_val();
    builder.setInsertionPointToStart(block);
    for (BlockArgument argument : block->getArguments())
      replaced += replaceWithConstant(solver, folder, builder, argument);
    for (Operation &op : llvm::make_early_inc_range(*block)) {
      Attribute held;
      if (matchPattern(&op, m_Constant(&held))) {
        folder.insertKnownConstant(&op, held);
        continue;
      }
      builder.setInsertionPoint(&op);
      unsigned before = replaced;
      for (Value result : op.getResults())
        replaced += replaceWithConstant(solver, folder, builder, result);
      if (op.getNumResults() != 0 && replaced - before == op.getNumResults() &&
          wouldOpBeTriviallyDead(&op)) {
        op.erase();
        continue;
      }
      enqueue(op.getRegions());
    }
  }
  return replaced;
}

struct IdrConstantsPass : idr::impl::IdrConstantsBase<IdrConstantsPass> {
  void runOnOperation() override {
    idr::FuncOp fn = getOperation();
    auto summaries = getCachedParentAnalysis<idr::ConstantSummaries>();
    if (!summaries) {
      fn.emitError("internal error: idr-constants runs inside idr-optimize, which holds the "
                   "constants summaries of its module");
      return signalPassFailure();
    }
    // A function holds no symbol table, so the solve resolves no callee:
    // every call is the hook's.
    DataFlowSolver solver(DataFlowConfig().setInterprocedural(false));
    solver.load<dataflow::DeadCodeAnalysis>();
    solver.load<idr::SummarizedConstantPropagation>(summaries->get());
    if (failed(solver.initializeAndRun(fn)))
      return signalPassFailure();
    unsigned replaced = rewrite(solver, fn);
    numConstants += replaced;
    if (replaced == 0)
      markAllAnalysesPreserved();
  }
};

} // namespace
