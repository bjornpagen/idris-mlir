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
// The summaries are on the nodes of idr-optimize's ready set for the run,
// which the step is given when it is made; a function never reads another
// function's body.
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
#include "idr/Transforms/InnerPasses.h.inc"
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

// The rewrite of the solve over a body, each block before the regions its
// ops hold, so that a constant met first is the one the folder hands out
// for its value. An op every result of which became a constant goes when
// nothing else keeps it, its regions with it. The walk recurses on the
// regions, each smaller than the block that holds it.
class Rewrite {
public:
  Rewrite(DataFlowSolver &solver, MLIRContext *context)
      : solver(solver), folder(context), builder(context) {}

  // The regions of the last op first, each region's blocks in order, as
  // the solve's own walk would leave them to the folder.
  void regions(MutableArrayRef<Region> held) {
    for (Region &region : llvm::reverse(held))
      for (Block &block : region)
        visit(block);
  }

  Rewritten done() {
    out.changed = out.changed || out.replaced != 0;
    return out;
  }

private:
  void visit(Block &block) {
    builder.setInsertionPointToStart(&block);
    for (BlockArgument argument : block.getArguments())
      out.replaced += replaceWithConstant(solver, folder, builder, argument);
    SmallVector<Operation *> holding;
    for (Operation &op : llvm::make_early_inc_range(block)) {
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
      if (op.getNumRegions() != 0)
        holding.push_back(&op);
    }
    for (Operation *op : llvm::reverse(holding))
      regions(op->getRegions());
  }

  DataFlowSolver &solver;
  OperationFolder folder;
  OpBuilder builder;
  Rewritten out;
};

Rewritten rewrite(DataFlowSolver &solver, idr::FuncOp fn) {
  Rewrite walk(solver, fn.getContext());
  walk.regions(fn->getRegions());
  return walk.done();
}

struct IdrConstantsPass : idr::impl::IdrConstantsBase<IdrConstantsPass> {
  IdrConstantsPass(const idr::optimize::ReadySet &set, Pass::Statistic &numConstants)
      : set(set), numConstants(numConstants) {}

  void runOnOperation() override {
    idr::FuncOp fn = getOperation();
    auto constantsOf = [&](StringAttr callee) -> const idr::ConstantResults * {
      const idr::optimize::Summary *summary = set.summaryOf(callee);
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

  const idr::optimize::ReadySet &set;
  Pass::Statistic &numConstants;
};

} // namespace

std::unique_ptr<Pass> idr::optimize::createConstants(const ReadySet &set,
                                                     Pass::Statistic &constants) {
  return std::make_unique<IdrConstantsPass>(set, constants);
}

