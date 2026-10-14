// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-specialize: one run raises, then specializes, every call of every
// function, and of every clone made on the way, and calls the clones.
//
// It works in generations. The first is the calls of the functions present
// when the run starts, read from References, which resolved each callee.
// A generation's calls are rewritten in order on the pass thread; the
// clones it made are then simplified in parallel, and their calls are the
// next generation. This computes what rewriting one call at a time would:
// a clone made in a run has no binding times in that run, so no call
// specializes on it and nothing reads its body before the boundary; each
// call names a callee that existed when it was collected; and simplifying a
// clone reads only the clone, declarations and other functions'
// signatures, none of which a generation changes. The run ends when a
// generation makes no clone.
#include "idr/IR/IdrDialect.h"
#include "idr/Analysis/Specialize.h"
#include "idr/Transforms/Specialize.h"
#include "idr/Analysis/Holds.h"
#include "idr/Analysis/References.h"
#include "idr/IR/Layout.h"
#include "idr/IR/TypeGraph.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/Threading.h"

namespace idr {
#define GEN_PASS_DEF_IDRSPECIALIZE
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace idr::specialize {

Specializer::Specializer(ModuleOp module, SymbolTable &symbols, const References &references,
                         CloneTable &clones, const BindingTimes &times, const Holds &holds,
                         const FrozenRewritePatternSet &patterns)
    : module(module), symbols(symbols), references(references), clones(clones), times(times),
      holds(holds), patterns(patterns), rewriter(module.getContext()) {}

LogicalResult Specializer::run() {
  SmallVector<Call> generation;
  for (auto fn : module.getOps<idr::FuncOp>())
    for (const References::Site &site : references.of(fn))
      if (auto call = dyn_cast<idr::CallOp>(site.at))
        generation.push_back({call, site.target});
  while (true) {
    for (auto [call, callee] : generation) {
      // Raising takes the apply that consumes the call's result into the
      // callee; the raised call's result is in turn applied where the
      // callee's result was a function, so raising again takes that apply
      // too. Each raise removes one apply from the caller, so this ends,
      // and it ends in this run: the raised call sits in a caller no later
      // generation reads, so stopping at one would leave one apply per
      // round of the simplify loop.
      while (true) {
        FailureOr<Raised> raised = raise(call, callee);
        if (failed(raised))
          return failure();
        if (!raised->call)
          break;
        call = raised->call;
        callee = raised->callee;
      }
      // The raised call, if any, is the one to specialize, and it names the
      // clone raising just called.
      if (failed(specialize(call, callee)))
        return failure();
    }
    if (made.empty())
      return success();
    SmallVector<Slot> slots(made.size());
    mlir::parallelFor(module.getContext(), 0, made.size(), [&](size_t i) {
      slots[i] = canonicalizeAndCollect(made[i].clone, patterns, symbols);
    });
    generation = settle(made, slots);
    made.clear();
  }
}

} // namespace idr::specialize

namespace {

struct Specialize : idr::impl::IdrSpecializeBase<Specialize> {
  // The canonicalization patterns of every loaded dialect and registered
  // op, as upstream's canonicalizer gathers them: from the context alone,
  // once per pipeline run, and shared by every worker and every copy of the
  // pass.
  LogicalResult initialize(MLIRContext *ctx) override {
    RewritePatternSet set(ctx);
    for (Dialect *dialect : ctx->getLoadedDialects())
      dialect->getCanonicalizationPatterns(set);
    for (RegisteredOperationName op : ctx->getRegisteredOperations())
      op.getCanonicalizationPatterns(set, ctx);
    patterns = FrozenRewritePatternSet(std::move(set));
    return success();
  }

  void runOnOperation() override {
    ModuleOp module = getOperation();
    // Held for the run, which runs no pipeline that would drop them.
    SymbolTable &symbols = getAnalysis<SymbolTable>();
    const idr::References &references = getAnalysis<idr::References>();
    idr::CloneTable &clones = getAnalysis<idr::CloneTable>();
    const idr::BindingTimes &times = getAnalysis<idr::BindingTimes>();
    const idr::Holds &holds = getAnalysis<idr::Holds>();
    idr::specialize::Specializer specializer(module, symbols, references, clones, times, holds,
                                             patterns);
    LogicalResult result = specializer.run();
    const idr::specialize::Statistics &stats = specializer.stats;
    numClones += stats.clones;
    numRaised += stats.raised;
    numShared += stats.shared;
    numFree += stats.free;
    numFixed += stats.fixed;
    numDecreasing += stats.decreasing;
    numBounded += stats.bounded;
    if (failed(result))
      return signalPassFailure();
    if (!specializer.changed) {
      markAllAnalysesPreserved();
      return;
    }
    // Every clone went in through the table and into CloneTable, and no
    // declaration changed. What reads bodies or calls is stale.
    markAnalysesPreserved<SymbolTable, idr::CloneTable, idr::Holds, idr::TypeGraph,
                          idr::Layouts>();
  }

  FrozenRewritePatternSet patterns;
};

} // namespace
