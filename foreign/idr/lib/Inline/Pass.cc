// idr-inline: MLIR's inliner, deciding what to inline as idr.inlining
// does. A caller that takes in a body without Idris's proof of termination
// loses its own (facts::inlined). A body is inlined as it is; the simplify
// round canonicalizes the module afterwards.

#include "idr/Idr.h"

#include "mlir/Analysis/CallGraph.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Transforms/Inliner.h"

#include <limits>

using namespace mlir;

namespace idr {
#define GEN_PASS_DEF_IDRINLINE
#include "idr/Passes.h.inc"
} // namespace idr

import idr.facts;
import idr.inlining;

namespace {

struct Inline : idr::impl::IdrInlineBase<Inline> {
  using IdrInlineBase::IdrInlineBase;

  void runOnOperation() override {
    ModuleOp module = getOperation();
    // The decisions look callees up in this table. The fold records the
    // functions it builds into the same table, so a later lookup does not
    // walk the module again.
    SymbolTable &table = getAnalysis<SymbolTable>();
    // Opened before the call graph: the fold builds functions, and the
    // graph has to contain them and the calls in their bodies.
    idr::SymbolScope symbols(module, table);
    // Data declarations do not change. The fold remembers whether a type
    // may hold a world or a closure instead of walking it for every call
    // it tests for deadness.
    idr::HoldMemo memo(module.getContext());
    idr::prepareForceAtCapture(module);
    idr::inlining::Decisions decisions = idr::inlining::decide(module, table);
    numInlinable += decisions.inlined.size();
    numLeaves += decisions.leaves;

    InlinerConfig config;
    // Until an iteration inlines nothing: the size rule, decided once,
    // bounds what can be inlined. A body is inlined as it is.
    config.setMaxInliningIterations(std::numeric_limits<unsigned>::max());
    config.setCloneCallback([clone = config.getCloneCallback()](
                                OpBuilder &builder, Region *src, Block *inlineBlock,
                                Block *postInsertBlock, IRMapping &mapper, bool cloned) {
      Operation *at = inlineBlock->getParentOp();
      auto into = isa<func::FuncOp>(at) ? cast<func::FuncOp>(at) : at->getParentOfType<func::FuncOp>();
      if (into)
        idr::facts::inlined(into, dyn_cast<func::FuncOp>(src->getParentOp()));
      clone(builder, src, inlineBlock, postInsertBlock, mapper, cloned);
    });
    auto profitable = [&](const Inliner::ResolvedCall &call) {
      Region *region = call.targetNode->getCallableRegion();
      return region && decisions.inlined.contains(region->getParentOp());
    };
    // Built after the fold, not taken from a preserved analysis: the fold
    // adds functions, and a graph from before this pass does not have them.
    CallGraph graph(module);
    // The inliner asks for a pipeline runner. None is installed, so the
    // runner is not called.
    Inliner inliner(module, graph, *this, getAnalysisManager(),
                    [](Pass &, OpPassManager &, Operation *) { return success(); }, config,
                    profitable);
    // Inlining a call and erasing a dead function rewrite the module. The
    // fingerprint is that rewrite.
    OperationFingerPrint before(module);
    if (failed(inliner.doInlining()))
      return signalPassFailure();
    // Nothing was rewritten. Preserving every analysis skips the walk of
    // every nested operation.
    if (before == OperationFingerPrint(module))
      markAllAnalysesPreserved();
  }

  // The scope around the fold is held by the context's idr dialect, which
  // must be loaded before the pass manager runs.
  void getDependentDialects(DialectRegistry &registry) const override {
    registry.insert<idr::IdrDialect>();
  }
};

} // namespace
