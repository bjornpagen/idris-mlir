// idr-inline: the force preparation, then MLIR's inliner, deciding what to
// inline as InlineDecisions does. A caller that takes in a body without
// Idris's proof of termination loses its own (FuncOp::absorb).
//
// Between iterations the inliner canonicalizes and CSEs the functions of a
// component, so that an apply one iteration exposed is a call the next one
// inlines: a do block unfolds in one round. It does so only on a function
// an iteration inlined into. Every other function is as the round's
// parallel function step left it, and the inliner optimizes one component
// at a time, so running the pipeline on it would canonicalize the module a
// second time, serially across components.
//
// The preparation and the inliner repeat together until a cycle of the
// two changes nothing: inlining one statement of a do block exposes the
// next statement's force, which only the preparation turns into a call,
// so one preparation per round would unfold one statement per round and
// a long do block would spend the round budget on its length. A cycle
// that returns the module to a shape an earlier cycle left stops there:
// the next cycle would repeat it.

#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Inline.h"
#include "idr/Analysis/Inline.h"
#include "idr/Analysis/References.h"
#include "idr/Analysis/Holds.h"
#include "idr/IR/TypeGraph.h"
#include "idr/IR/Layout.h"

#include "mlir/Analysis/CallGraph.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Transforms/Inliner.h"
#include "mlir/Transforms/Passes.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"

#include <limits>

using namespace mlir;

namespace idr {
#define GEN_PASS_DEF_IDRINLINE
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

namespace {

// What the inliner runs on a function an iteration inlined into. Every
// callable is an idr.func, so this one pipeline is anchored there.
void componentPipeline(OpPassManager &pm) {
  pm.addPass(createCanonicalizerPass());
  pm.addPass(createCSEPass());
}

struct Inline : idr::impl::IdrInlineBase<Inline> {
  using IdrInlineBase::IdrInlineBase;

  void runOnOperation() override {
    ModuleOp module = getOperation();
    // The preparation changes no idr.data or idr.ctor and enters every
    // function it builds through the SymbolTable analysis.
    AnalysisManager::PreservedAnalyses kept;
    kept.preserve<SymbolTable, idr::Holds, idr::TypeGraph, idr::Layouts>();

    bool everPrepared = false;
    bool everInlined = false;
    bool counted = false;
    SmallVector<OperationFingerPrint> seen;
    for (;;) {
      OperationFingerPrint cycleStart(module);
      if (llvm::is_contained(seen, cycleStart)) {
        markAnalysesPreserved<idr::Holds, idr::TypeGraph, idr::Layouts>();
        return;
      }
      seen.push_back(cycleStart);
      // Before any decision or graph: the decisions must count the calls the
      // preparation makes, and the graph must hold the functions it builds.
      bool captured = false;
      SmallVector<idr::FuncOp> wrappers = idr::inlining::forceWrappers(module);
      if (!wrappers.empty())
        captured = idr::inlining::forceAtCapture(module, getAnalysis<SymbolTable>(), wrappers);
      if (captured)
        getAnalysisManager().invalidate(kept);
      bool forced =
          idr::inlining::forceOfOneConstant(module, getAnalysis<idr::References>());
      if (forced)
        getAnalysisManager().invalidate(kept);
      bool prepared = captured || forced;
      everPrepared = everPrepared || prepared;

      idr::InlineDecisions &decisions = getAnalysis<idr::InlineDecisions>();
      if (!counted) {
        counted = true;
        numInlinable += decisions.inlinable();
        numLeaves += decisions.leaves();
      }
      // Taken after the last invalidation, so References and the decisions are
      // current when the inliner changes nothing.
      auto preserveUnchanged = [&] {
        if (!everPrepared && !everInlined)
          return markAllAnalysesPreserved();
        // References and the decisions were taken after this cycle's last
        // invalidation, so they are current. The SymbolTable is current
        // only where the inliner never ran: it erases without it.
        if (everInlined)
          markAnalysesPreserved<idr::Holds, idr::TypeGraph, idr::Layouts, idr::References,
                                idr::InlineDecisions>();
        else
          markAnalysesPreserved<SymbolTable, idr::Holds, idr::TypeGraph, idr::Layouts,
                                idr::References, idr::InlineDecisions>();
      };
      // No call names an inlinable function, so no iteration would inline: the
      // usual case once the rounds near the fixpoint, which then build no call
      // graph. The preparation is at its own fixpoint then too: without
      // inlining, no cycle exposes another force.
      if (decisions.inlinableCalls() == 0)
        return preserveUnchanged();

      // Plain values from here: the inliner runs pipelines on nested functions
      // and erases functions, and no analysis of ours is read while it does.
      llvm::DenseSet<Operation *> inlinable = decisions.inlined();
      // Every function has its entry before the inliner starts, so the map
      // never rehashes while its runners read it from several threads.
      llvm::DenseMap<Operation *, bool> marks;
      for (idr::FuncOp fn : module.getOps<idr::FuncOp>())
        marks.try_emplace(fn, false);

      InlinerConfig config;
      config.setDefaultPipeline(componentPipeline);
      // Until an iteration inlines nothing: the size rule, decided once, bounds
      // what can be inlined, and a do block of n statements needs n iterations.
      config.setMaxInliningIterations(std::numeric_limits<unsigned>::max());
      // On the pass thread, in the inliner's sequential phase.
      config.setCloneCallback([&marks, clone = config.getCloneCallback()](
                                  OpBuilder &builder, Region *src, Block *inlineBlock,
                                  Block *postInsertBlock, IRMapping &mapper, bool cloned) {
        if (auto into = inlineBlock->getParent()->getParentOfType<idr::FuncOp>()) {
          into.absorb(dyn_cast<idr::FuncOp>(src->getParentOp()));
          if (auto it = marks.find(into); it != marks.end())
            it->second = true;
        }
        clone(builder, src, inlineBlock, postInsertBlock, mapper, cloned);
      });
      auto profitable = [&inlinable](const Inliner::ResolvedCall &call) {
        Region *region = call.targetNode->getCallableRegion();
        return region && inlinable.contains(region->getParentOp());
      };
      // A function nothing was inlined into is as the round's function step
      // left it; canonicalizing it again would cost a serial walk of it. The
      // inliner calls this from its workers, one function each: a runner reads
      // and clears only its own entry. runPipeline runs the pipeline with the
      // verifier and the manager's instrumentation, so its passes are timed
      // under this one.
      auto runner = [this, &marks](Pass &, OpPassManager &pipeline, Operation *op) -> LogicalResult {
        auto it = marks.find(op);
        if (it == marks.end() || !it->second)
          return success();
        it->second = false;
        return runPipeline(pipeline, op);
      };

      // The inliner also erases a function that was dead before it started,
      // with nothing inlined, so the module itself says whether it changed.
      OperationFingerPrint before(module);
      // Taken after the preparation, so it holds what the preparation built. A
      // pipeline on a nested function runs under that function's own manager,
      // so the module's analyses, this graph among them, stand meanwhile.
      CallGraph &graph = getAnalysis<CallGraph>();
      Inliner inliner(module, graph, *this, getAnalysisManager(), runner, config, profitable);
      if (failed(inliner.doInlining()))
        return signalPassFailure();
      if (before == OperationFingerPrint(module) && !prepared)
        return preserveUnchanged();
      everInlined = true;
      // A marked body may have been rewritten anywhere by its pipeline, and the
      // inliner erases the functions it left dead, and those that were dead
      // already, without the SymbolTable analysis: only the declarations stand
      // for the next cycle to read.
      AnalysisManager::PreservedAnalyses declarations;
      declarations.preserve<idr::Holds, idr::TypeGraph, idr::Layouts>();
      getAnalysisManager().invalidate(declarations);
    }
  }

  // A pipeline run from inside a pass loads no dialect, so the component
  // pipeline's are loaded before the manager runs.
  void getDependentDialects(DialectRegistry &registry) const override {
    OpPassManager pm(idr::FuncOp::getOperationName());
    componentPipeline(pm);
    pm.getDependentDialects(registry);
  }
};

} // namespace
