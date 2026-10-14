// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-inline: the force preparation, then MLIR's inliner, deciding what to
// inline as InlineDecisions does. A caller that takes in a body without
// Idris's proof of termination loses its own (FuncOp::absorb).
//
// Between iterations the inliner canonicalizes the ops an iteration
// inlined (InlineCleanup, below), so that an apply one iteration exposed
// is a call the next one inlines: a do block unfolds in one round. It
// does so only on a function an iteration inlined into. Every other
// function is as the round's parallel function step left it, and the
// inliner optimizes one component at a time, so running the pipeline on
// it would canonicalize the module a second time, serially across
// components.
//
// The preparation and the inliner repeat together until a cycle of the
// two changes nothing: inlining one statement of a do block exposes the
// next statement's force, which only the preparation turns into a call,
// so one preparation per round would unfold one statement per round and
// a long do block would spend the round budget on its length. A cycle
// that returns the module to a shape an earlier cycle left stops there:
// the next cycle would repeat it.

#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Canonicalize.h"
#include "idr/Transforms/Inline.h"
#include "idr/Analysis/Inline.h"
#include "idr/Analysis/References.h"
#include "idr/Analysis/Holds.h"
#include "idr/IR/TypeGraph.h"
#include "idr/IR/Layout.h"

#include "mlir/Analysis/CallGraph.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"
#include "mlir/Transforms/Inliner.h"
#include "mlir/Transforms/Passes.h"
#include "mlir/Transforms/RegionUtils.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"

#include <limits>
#include <memory>

using namespace mlir;

namespace idr {
#define GEN_PASS_DEF_IDRINLINE
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

namespace {

// What the inliner runs on a function an iteration inlined into. Every
// callable is an idr.func, so this one pipeline is anchored there.
//
// Between inlining iterations only what inlining itself exposed needs
// folding -- an apply of a known closure, a match on a known
// constructor -- so that the next iteration reads it as a call. The
// clone callback marks the ops a clone inserted with this attribute,
// and the cleanup below runs the canonicalization patterns on those
// ops and their immediate neighbours alone, the driver following
// operands and users from there. Canonicalizing the whole
// body instead re-walks it once per inlining iteration that touched
// it: a function at the head of a long chain of inlines (the root of
// a large program) is marked hundreds of times, each run trying every
// pattern on tens of thousands of ops the round's function step
// already canonicalized, and each run but the last is discarded by
// the next inline into it. What the scoped run cannot reach -- a
// defining op outside the marks that must fold first, region
// simplification, the duplicates a CSE would merge -- the next
// round's parallel canonicalize and CSE do, in full, once.
constexpr StringLiteral kSeedAttr = "idr.inlined";

struct InlineCleanup : PassWrapper<InlineCleanup, OperationPass<idr::FuncOp>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(InlineCleanup)

  StringRef getArgument() const final { return "idr-inline-cleanup"; }
  StringRef getDescription() const final {
    return "Canonicalize the ops an inlining iteration inserted";
  }

  // The canonicalization patterns of every loaded dialect, as the
  // canonicalizer pass collects them, frozen once per pass copy.
  LogicalResult initialize(MLIRContext *context) override {
    RewritePatternSet owning(context);
    for (Dialect *dialect : context->getLoadedDialects())
      dialect->getCanonicalizationPatterns(owning);
    for (RegisteredOperationName op : context->getRegisteredOperations())
      op.getCanonicalizationPatterns(owning, context);
    patterns = std::make_shared<FrozenRewritePatternSet>(std::move(owning));
    return success();
  }

  void runOnOperation() override {
    idr::FuncOp fn = getOperation();
    bool marked = false;
    fn.walk([&](Operation *op) {
      if (op->hasAttr(kSeedAttr)) {
        marked = true;
        return WalkResult::interrupt();
      }
      return WalkResult::advance();
    });
    if (!marked)
      return markAllAnalysesPreserved();
    IRRewriter rewriter(fn.getContext());
    // As the greedy driver does before its patterns: a body inlined
    // here may end in ub.unreachable, leaving the continuation no
    // path reaches, and patterns are unsafe on unreachable ops. The
    // marks on the erased ops go with them; the seeds are read off
    // what is left.
    (void)eraseUnreachableBlocks(rewriter, fn.getBody());
    SmallVector<Operation *> seeds;
    fn.walk([&](Operation *op) {
      if (op->hasAttr(kSeedAttr)) {
        op->removeAttr(kSeedAttr);
        seeds.push_back(op);
      }
    });
    // What inlining exposed is as often in the caller as in the body
    // it inserted: an apply of the closure the body returns, a match
    // on the constructor an inserted op reads a field of. The driver
    // follows operands and users of an op it rewrites, but an op it
    // never visits stays unvisited however its neighbours changed, so
    // the seeds are joined by their immediate users and the ops that
    // define their operands.
    llvm::DenseSet<Operation *> seen(seeds.begin(), seeds.end());
    auto join = [&](Operation *op) {
      if (op && fn->isAncestor(op) && seen.insert(op).second)
        seeds.push_back(op);
    };
    for (size_t at = 0, count = seeds.size(); at < count; ++at) {
      Operation *op = seeds[at];
      for (Value result : op->getResults())
        for (Operation *user : result.getUsers())
          join(user);
      for (Value operand : op->getOperands())
        join(operand.getDefiningOp());
    }
    if (!seeds.empty()) {
      GreedyRewriteConfig config;
      config.setScope(&fn.getBody());
      // Best-effort, as canonicalization is: non-convergence leaves
      // valid IR for the next round's full canonicalize.
      (void)applyOpPatternsGreedily(seeds, *patterns, config);
    }
    // The structural half of a canonicalize, which the op-list
    // driver does not do: dead block arguments and the blocks the
    // patterns left unreachable. No block merging, as under the
    // canonicalizer's normal region simplification.
    (void)simplifyRegions(rewriter, fn.getBody(), /*mergeBlocks=*/false);
  }

  std::shared_ptr<const FrozenRewritePatternSet> patterns;
};

void componentPipeline(OpPassManager &pm) { pm.addPass(std::make_unique<InlineCleanup>()); }

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
      bool clonedAny = false;
      // On the pass thread, in the inliner's sequential phase.
      config.setCloneCallback([&marks, &clonedAny, clone = config.getCloneCallback()](
                                  OpBuilder &builder, Region *src, Block *inlineBlock,
                                  Block *postInsertBlock, IRMapping &mapper, bool cloned) {
        clonedAny = true;
        if (auto into = inlineBlock->getParent()->getParentOfType<idr::FuncOp>()) {
          into.absorb(dyn_cast<idr::FuncOp>(src->getParentOp()));
          if (auto it = marks.find(into); it != marks.end())
            it->second = true;
        }
        clone(builder, src, inlineBlock, postInsertBlock, mapper, cloned);
        // The ops just inserted, in the blocks the clone made between
        // the call's block and its continuation: the seeds of the
        // cleanup the runner runs on this function. An attribute, not
        // a list of pointers: inlining goes on erasing and merging
        // around them before the cleanup reads the marks off the ops
        // that are still there.
        UnitAttr seed = UnitAttr::get(builder.getContext());
        for (Block &block : llvm::make_range(std::next(inlineBlock->getIterator()),
                                             postInsertBlock->getIterator()))
          block.walk([&](Operation *op) { op->setAttr(kSeedAttr, seed); });
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
      // with nothing inlined. A clone (the callback above) or a change in
      // the function count is every change it makes: the pipelines it runs
      // touch only marked functions, which only a clone marks, and it
      // otherwise erases dead callables. Two whole-module fingerprints per
      // cycle bought nothing over those signals; the cycle guard above
      // keeps the one hash that detects a returning shape.
      auto functionsBefore = llvm::range_size(module.getOps<idr::FuncOp>());
      clonedAny = false;
      // A pipeline on a nested function runs under that function's own
      // manager, so the module's analyses, this graph among them, stand
      // meanwhile.
      CallGraph &graph = getAnalysis<CallGraph>();
      Inliner inliner(module, graph, *this, getAnalysisManager(), runner, config, profitable);
      if (failed(inliner.doInlining()))
        return signalPassFailure();
      // A function the inliner never ran the cleanup on (one holding a
      // nested callable, which its SCC step skips) keeps its seed
      // marks; no mark outlives the cycle that made it.
      if (clonedAny)
        for (idr::FuncOp fn : module.getOps<idr::FuncOp>())
          fn.walk([&](Operation *op) { op->removeAttr(kSeedAttr); });
      if (!clonedAny && functionsBefore == llvm::range_size(module.getOps<idr::FuncOp>()) && !prepared)
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
