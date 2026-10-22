// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-constants: sparse conditional constant propagation through one
// function, as upstream's solver and analyses do it, with a call's results
// taken from what its callee returns once the callee's component of the
// schedule is final. It is the last step of idr-optimize's inner pipeline,
// so that a function's final body states its own summary: every value the
// solve holds constant is a constant op when the step ends, a return's
// operands among them, and the schedule reads the summary from there when
// the component finishes. A replacement an action handler skips leaves the
// value as it was, and the summary knows that much less of it.
//
// The summaries are the schedule's for the run, which the step is given
// when it is made; a function never reads another function's body. A call
// of a callee not final (of the function's own component, or a copy not
// yet placed) assumes nothing of it: unknown at every result, the state
// upstream's solve starts a value it cannot see from.
#include "idr/Transforms/Effects.h"

#include "idr/Analysis/Constants.h"
#include "idr/IR/Effects/Whole.h"
#include "idr/IR/Generated/Actions.h.inc"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Actions.h"
#include "idr/Transforms/Optimize.h"

#include "mlir/Analysis/DataFlow/DeadCodeAnalysis.h"
#include "mlir/Analysis/DataFlowFramework.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/Matchers.h"
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

// idr-constants gives one value's uses its constant; the unit is the
// value's defining op, or for a block argument its block's parent op.
struct ConstantsReplaceAction : idr::support::TaggedAction<ConstantsReplaceAction> {
  using TaggedAction::TaggedAction;
  static constexpr std::string_view tag = ::idr::actions::constantsReplace;
};

// idr-constants erases one op every result of which became a constant; the
// unit is the op.
struct ConstantsEraseAction : idr::support::TaggedAction<ConstantsEraseAction> {
  using TaggedAction::TaggedAction;
  static constexpr std::string_view tag = ::idr::actions::constantsErase;
};

// idr-constants hands one constant already in the body to the folder,
// which may move it to its block's front or merge it into an equal one met
// before; the unit is the constant.
struct ConstantsUniqueAction : idr::support::TaggedAction<ConstantsUniqueAction> {
  using TaggedAction::TaggedAction;
  static constexpr std::string_view tag = ::idr::actions::constantsUnique;
};

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
  Value made;
  Operation *unit =
      value.getDefiningOp() ? value.getDefiningOp() : value.getParentBlock()->getParentOp();
  (void)idr::support::perform<ConstantsReplaceAction>(unit, [&] {
    made = folder.getOrCreateConstant(builder.getInsertionBlock(),
                                      lattice->getValue().getConstantDialect(), constant,
                                      value.getType());
    if (made)
      value.replaceAllUsesWith(made);
  });
  return static_cast<bool>(made);
}

// What the rewrite did: how many values it replaced, and whether it
// changed the body at all. Gathering the constants already there may move
// one to the front of its region, or replace one by an equal one met
// before, without replacing any value the solve found.
struct Rewritten {
  unsigned replaced = 0;
  bool changed = false;
};

// The rewrite of the solve over a body, one block at a time. An op every
// result of which became a constant goes when the effect system says it,
// with everything in it, only computes them: a crash or a divergence it may
// reach stays where evaluation reaches it.
class Rewrite {
public:
  Rewrite(DataFlowSolver &solver, MLIRContext *context)
      : solver(solver), folder(context), builder(context) {}

  // One block: its arguments, then its ops in order.
  void block(Block &block) {
    builder.setInsertionPointToStart(&block);
    for (BlockArgument argument : block.getArguments())
      out.replaced += replaceWithConstant(solver, folder, builder, argument);
    for (Operation &op : llvm::make_early_inc_range(block)) {
      Attribute held;
      if (matchPattern(&op, m_Constant(&held))) {
        (void)idr::support::perform<ConstantsUniqueAction>(&op, [&] {
          Block *in = op.getBlock();
          Operation *before = op.getPrevNode();
          // False when `op` was replaced, and so erased.
          bool kept = folder.insertKnownConstant(&op, held);
          out.changed = out.changed || !kept || op.getBlock() != in || op.getPrevNode() != before;
        });
        continue;
      }
      builder.setInsertionPoint(&op);
      unsigned before = out.replaced;
      for (Value result : op.getResults())
        out.replaced += replaceWithConstant(solver, folder, builder, result);
      if (op.getNumResults() != 0 && out.replaced - before == op.getNumResults() &&
          op.use_empty() && idr::effects::whole(&op).onlyComputes())
        (void)idr::support::perform<ConstantsEraseAction>(&op, [&] { op.erase(); });
    }
  }

  Rewritten done() {
    out.changed = out.changed || out.replaced != 0;
    return out;
  }

private:
  DataFlowSolver &solver;
  OperationFolder folder;
  OpBuilder builder;
  Rewritten out;
};

// MLIR's walk, in pre-order, hands the rewrite each block before the
// regions its ops hold, so a constant met first is the one the folder
// hands out for its value; and it reads a block's ops only after the
// rewrite is done with them, so an op erased there takes its regions with
// it unread. It keeps its place in a stack of its own, so a body nested
// deep needs no deeper native stack.
Rewritten rewrite(DataFlowSolver &solver, idr::FuncOp fn) {
  Rewrite step(solver, fn.getContext());
  fn->walk<WalkOrder::PreOrder>([&](Block *block) { step.block(*block); });
  return step.done();
}

struct IdrConstantsPass : idr::impl::IdrConstantsBase<IdrConstantsPass> {
  IdrConstantsPass(const idr::optimize::Schedule &schedule, Pass::Statistic &numConstants)
      : schedule(schedule), numConstants(numConstants) {}

  void runOnOperation() override {
    idr::FuncOp fn = getOperation();
    auto constantsOf = [&](idr::CallOp call) -> idr::ConstantResults {
      using idr::optimize::FunctionId;
      if (std::optional<FunctionId> callee = schedule.graph.find(call.getCalleeAttr()))
        if (const idr::optimize::Summary *final = schedule.summaryOf(*callee))
          return final->constants;
      return idr::ConstantResults(call->getNumResults(), ConstantValue::getUnknownConstant());
    };
    // A function holds no symbol table, so the solve resolves no callee:
    // every call is the hook's.
    DataFlowSolver solver(DataFlowConfig().setInterprocedural(false));
    solver.load<dataflow::DeadCodeAnalysis>();
    solver.load<idr::SummarizedConstantPropagation<decltype(constantsOf)>>(constantsOf);
    if (failed(solver.initializeAndRun(fn)))
      return signalPassFailure();
    Rewritten done = rewrite(solver, fn);
    numConstants += done.replaced;
    if (!done.changed)
      markAllAnalysesPreserved();
  }

  const idr::optimize::Schedule &schedule;
  Pass::Statistic &numConstants;
};

} // namespace

std::unique_ptr<Pass> idr::optimize::createConstants(const Schedule &schedule,
                                                     Pass::Statistic &constants) {
  return std::make_unique<IdrConstantsPass>(schedule, constants);
}

