// idr-inline: MLIR's inliner, deciding what to inline as idr.inlining
// does. A caller that takes in a body without Idris's proof of termination
// loses its own (facts::inlined).

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

  // The default pipeline is parsed once, here, so that a pipeline that does
  // not parse fails the pass instead of running nothing on every function.
  LogicalResult initialize(MLIRContext *ctx) override {
    std::string text = defaultPipeline;
    std::string error;
    llvm::raw_string_ostream os(error);
    OpPassManager parsed;
    if (failed(parsePassPipeline(text, parsed, os)))
      return emitError(UnknownLoc::get(ctx))
             << "idr-inline: the default pipeline \"" << text
             << "\" does not parse: " << StringRef(error).trim();
    pipeline = std::move(parsed);
    return success();
  }

  void runOnOperation() override {
    ModuleOp module = getOperation();
    idr::inlining::Decisions decisions = idr::inlining::decide(module);
    numInlinable += decisions.inlined.size();
    numLeaves += decisions.leaves;

    InlinerConfig config;
    // The inliner hands a pass manager anchored on the function's op; the
    // parsed pipeline, anchored on any op, runs there.
    config.setDefaultPipeline([this](OpPassManager &pm) { pm = pipeline; });
    unsigned iterations = maxIterations;
    config.setMaxInliningIterations(iterations ? iterations
                                               : std::numeric_limits<unsigned>::max());
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
    CallGraph &graph = getAnalysis<CallGraph>();
    // The module's symbols, for the pipeline it runs on each function
    // (idr-canonicalize): inlining adds none and erases the dead functions
    // only after the last pipeline has run.
    (void)getAnalysis<SymbolTable>();
    Inliner inliner(module, graph, *this, getAnalysisManager(), runPipelineHelper, config,
                    profitable);
    if (failed(inliner.doInlining()))
      signalPassFailure();
  }

  // A pipeline that does not parse loads nothing, and initialize reports
  // it.
  void getDependentDialects(DialectRegistry &registry) const override {
    OpPassManager pm(func::FuncOp::getOperationName());
    if (succeeded(parsePassPipeline(defaultPipeline, pm, llvm::nulls())))
      pm.getDependentDialects(registry);
  }

  // The inliner runs the default pipeline on each function as part of
  // this pass.
  static LogicalResult runPipelineHelper(Pass &pass, OpPassManager &pipeline, Operation *op) {
    return static_cast<Inline &>(pass).runPipeline(pipeline, op);
  }

  OpPassManager pipeline;
};

} // namespace
