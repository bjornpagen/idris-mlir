// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-narrow: the bigs and naturals integer range analysis proves fit a
// small become plain i64 words, and a loop whose natural only descends is
// versioned so that its copy proves it.
//
// The analysis is MLIR's, seeing our ops through their ranges, solved once
// for the module (Ranges); this pass only reads it and rewrites. Nothing it
// learns is stored: the rewritten IR is the fact. Versioning runs on the
// module, since a versioned loop's copy holds values the solve never saw
// and the module is solved again after it; the word rewrite then runs on
// each function in parallel, each verified on its own. A narrowed op
// becomes `arith` on the values, which idr.big.to_int and idr.big.from_int
// convert where the web meets a big it does not prove; the pairs they form
// inside a web fold away.

#include "idr/Transforms/Narrow.h"

#include "idr/Analysis/Holds.h"
#include "idr/Analysis/Ranges.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/TypeGraph.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Pass/AnalysisManager.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Rewrite/FrozenRewritePatternSet.h"
#include "mlir/Support/TypeID.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"
#include "mlir/Transforms/WalkPatternRewriteDriver.h"

#include "llvm/ADT/SmallVector.h"

namespace idr {
#define GEN_PASS_DEF_IDRNARROW
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace idr::narrow {

namespace {

// The word rewrite of one function, under the ranges idr-narrow solved for
// the module. It runs only inside idr-narrow and keeps no statistics: what
// it counts only says whether it changed anything.
struct NarrowWords : PassWrapper<NarrowWords, OperationPass<FuncOp>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(NarrowWords)

  StringRef getArgument() const final { return "idr-narrow-words"; }
  StringRef getDescription() const final {
    return "Make the bigs and naturals of one function proved to fit a small i64 words";
  }

  void runOnOperation() override {
    FuncOp fn = getOperation();
    std::optional<std::reference_wrapper<Ranges>> ranges = getCachedParentAnalysis<Ranges>();
    if (!ranges) {
      fn.emitError("internal error: idr-narrow: the ranges of the module are not available to "
                   "its functions");
      return signalPassFailure();
    }
    Facts facts(ranges->get());
    uint64_t carried = 0, narrowed = 0;
    // The joints first, while every value is still the one analysed; then
    // the ops, whose operands may by then be the bigs of words.
    {
      RewritePatternSet joints(&getContext());
      populateJointPatterns(joints, facts, carried);
      walkAndApplyPatterns(fn, std::move(joints));
    }
    {
      RewritePatternSet words(&getContext());
      populateWordPatterns(words, facts, narrowed);
      walkAndApplyPatterns(fn, std::move(words));
    }

    // A word made a big and back is the word; what no one reads goes: the
    // conversions made, a versioned loop's start once its copy took the
    // word, and a big made of a word that every reader now takes as the
    // word.
    SmallVector<Operation *> conversions;
    fn.walk([&](Operation *op) {
      if (facts.made(op) || isa<BigSmallOp, BigFromIntOp>(op))
        conversions.push_back(op);
    });
    GreedyRewriteConfig config;
    config.setStrictness(GreedyRewriteStrictness::ExistingAndNewOps)
        .setScope(&fn->getRegion(0));
    bool changed = false;
    (void)applyOpPatternsGreedily(conversions, FrozenRewritePatternSet(), config, &changed);
    if (carried == 0 && narrowed == 0 && !changed)
      markAllAnalysesPreserved();
  }
};

struct Narrow : idr::impl::IdrNarrowBase<Narrow> {
  using IdrNarrowBase::IdrNarrowBase;

  void runOnOperation() override {
    ModuleOp module = getOperation();
    auto unsolved = [&] {
      module.emitError("internal error: idr-narrow: the range analysis failed");
      signalPassFailure();
    };
    uint64_t versioned = 0;
    {
      const Ranges &ranges = getAnalysis<Ranges>();
      if (!ranges.valid())
        return unsolved();
      Facts facts(ranges);
      RewritePatternSet patterns(&getContext());
      populateVersionPatterns(patterns, facts, versioned);
      walkAndApplyPatterns(module, std::move(patterns));
    }
    // A versioned loop's copy holds values the first solve never saw, and
    // nothing else of the module is worth keeping across it. Otherwise the
    // first solve is the one the functions read.
    if (versioned != 0) {
      getAnalysisManager().invalidate(AnalysisManager::PreservedAnalyses());
      if (!getAnalysis<Ranges>().valid())
        return unsolved();
    }

    // The functions read the module's ranges as their parent's; no
    // reference to it is held across the nested run, after which it is
    // gone.
    OpPassManager nested(ModuleOp::getOperationName());
    nested.nest<FuncOp>().addPass(std::make_unique<NarrowWords>());
    if (failed(runPipeline(nested, module)))
      return signalPassFailure();
    numVersioned += versioned;
    // No declaration changes, and no symbol is added or removed.
    markAnalysesPreserved<Holds, TypeGraph, Layouts, SymbolTable>();
  }
};

} // namespace

} // namespace idr::narrow
