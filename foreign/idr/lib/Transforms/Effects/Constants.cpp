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
// The summaries are on the nodes of idr-optimize's ready set, cached on the
// program for the length of its run, and read here through the parent; a
// function never reads another function's body.
#include "idr/Transforms/Effects.h"

#include "idr/Analysis/Constants.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Optimize.h"

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

// What the rewrite did: how many values it replaced, and whether it
// changed the body at all. Gathering the constants already there may move
// one to the front of its region, or replace one by an equal one met
// before, without replacing any value the solve found.
struct Rewritten {
  unsigned replaced = 0;
  bool changed = false;
};

// The rewrite of the solve over the body of `fn`, blocks before the regions
// they hold, so that a constant met first is the one the folder hands out
// for its value. An op every result of which became a constant goes when
// nothing else keeps it, its regions with it.
Rewritten rewrite(DataFlowSolver &solver, idr::FuncOp fn) {
  OperationFolder folder(fn.getContext());
  OpBuilder builder(fn.getContext());
  Rewritten out;
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
      out.replaced += replaceWithConstant(solver, folder, builder, argument);
    for (Operation &op : llvm::make_early_inc_range(*block)) {
      Attribute held;
      if (matchPattern(&op, m_Constant(&held))) {
        Block *in = op.getBlock();
        Operation *before = op.getPrevNode();
        // False when `op` was replaced, and so erased.
        bool kept = folder.insertKnownConstant(&op, held);
        out.changed = out.changed || !kept || op.getBlock() != in || op.getPrevNode() != before;
        continue;
      }
      builder.setInsertionPoint(&op);
      unsigned before = out.replaced;
      for (Value result : op.getResults())
        out.replaced += replaceWithConstant(solver, folder, builder, result);
      if (op.getNumResults() != 0 && out.replaced - before == op.getNumResults() &&
          wouldOpBeTriviallyDead(&op)) {
        op.erase();
        continue;
      }
      enqueue(op.getRegions());
    }
  }
  out.changed = out.changed || out.replaced != 0;
  return out;
}

struct IdrConstantsPass : idr::impl::IdrConstantsBase<IdrConstantsPass> {
  void runOnOperation() override {
    idr::FuncOp fn = getOperation();
    auto set = getCachedParentAnalysis<idr::optimize::ReadySet>();
    if (!set) {
      fn.emitError("internal error: idr-constants runs inside idr-optimize, whose ready set "
                   "holds the summaries of its program");
      return signalPassFailure();
    }
    const idr::optimize::ReadySet &ready = set->get();
    auto constantsOf = [&](StringAttr callee) -> const idr::ConstantResults * {
      const idr::optimize::Summary *summary = ready.summaryOf(callee);
      return summary ? &summary->constants : nullptr;
    };
    // A function holds no symbol table, so the solve resolves no callee:
    // every call is the hook's.
    DataFlowSolver solver(DataFlowConfig().setInterprocedural(false));
    solver.load<dataflow::DeadCodeAnalysis>();
    solver.load<idr::SummarizedConstantPropagation>(constantsOf);
    if (failed(solver.initializeAndRun(fn)))
      return signalPassFailure();
    Rewritten done = rewrite(solver, fn);
    numConstants += done.replaced;
    if (!done.changed)
      markAllAnalysesPreserved();
  }
};

} // namespace
