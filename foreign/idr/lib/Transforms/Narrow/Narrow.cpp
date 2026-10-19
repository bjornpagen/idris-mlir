// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-narrow: the bigs and naturals integer range analysis proves fit a
// small become plain i64 words, and a loop whose natural only descends is
// versioned so that its copy proves it.
//
// The analysis is MLIR's, seeing our ops through their ranges, solved once
// for the program (Ranges, an analysis of the program's analysis manager);
// this pass only reads it and rewrites. Nothing it learns is stored: the
// rewritten IR is the fact. Versioning runs on the program, since a
// versioned loop's copy holds values the solve never saw, and the program
// is solved again after it; the word rewrite, idr-narrow-words, then runs
// on each function in parallel, each verified on its own, reading the
// program's solve from the parent's cache. A narrowed op becomes `arith` on
// the values, which idr.big.to_int and the bigs made of integers convert
// where the web meets a big it does not prove; the pairs they form inside a
// web fold away, under upstream's driver.

#include "idr/Transforms/Narrow.h"

#include "idr/Analysis/Ranges.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/TypeGraph.h"
#include "idr/Support/Actions.h"
#include "idr/Transforms/Pipeline.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Pass/AnalysisManager.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Rewrite/FrozenRewritePatternSet.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"
#include "mlir/Transforms/WalkPatternRewriteDriver.h"

#include "llvm/ADT/SmallVector.h"

#include <functional>

namespace idr {
#define GEN_PASS_DEF_IDRNARROW
#define GEN_PASS_DEF_IDRNARROWWORDS
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace idr::narrow {

namespace {

// idr-narrow folds the conversions of one function and erases those no one
// reads; the unit is the function.
struct NarrowFoldAction : support::TaggedAction<NarrowFoldAction> {
  using TaggedAction::TaggedAction;
  static constexpr llvm::StringLiteral tag = "idr-narrow-fold";
};

// The word rewrite of one function, under the ranges idr-narrow solved for
// the program and holds in its analysis manager while it runs this pass. It
// keeps no statistics: what it counts only says whether it changed
// anything.
struct NarrowWords : idr::impl::IdrNarrowWordsBase<NarrowWords> {
  void runOnProgram(ProgramOp program) override {
    FuncOp fn = getOperation();
    // Only idr-narrow solves the program's ranges and holds them, solved,
    // for this pass: run without it, there is nothing to read.
    FailureOr<std::reference_wrapper<const Ranges::Solved>> solved =
        [&]() -> FailureOr<std::reference_wrapper<const Ranges::Solved>> {
      if (std::optional<std::reference_wrapper<Ranges>> ranges =
              getCachedParentAnalysis<Ranges>(program))
        return ranges->get().solved();
      return failure();
    }();
    if (failed(solved)) {
      fn.emitError("internal error: idr-narrow-words: no solved Ranges of the program");
      return signalPassFailure();
    }
    Facts facts(*solved);
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

    // A word made a big and back is the word, and a conversion of a
    // constant is its constant: upstream's driver folds each conversion by
    // its own folder, and erases what no one reads (the conversions made, a
    // versioned loop's start once its copy took the word, and a big made of
    // a word that every reader now takes as the word, with the views
    // counting read such a big through, and a big constant whose readers
    // now read its word), these ops and no other.
    SmallVector<Operation *> conversions;
    auto conversion = [&](Operation *op) {
      return op && (facts.made(op) || isa<BigSmallOp, BigFromSIntOp, BigFromUIntOp>(op) ||
                    (isa<ConstantOp>(op) && isBig(op->getResult(0).getType())));
    };
    fn.walk<WalkOrder::PreOrder>([&](Operation *op) {
      if (conversion(op) || (op->hasTrait<ResultCarriesOperand>() &&
                             conversion(op->getOperand(0).getDefiningOp())))
        conversions.push_back(op);
    });
    // A conversion every reader of which now reads its word is made only to
    // be dropped: without its drops it is made for nothing, and erased.
    bool dropped = false;
    for (Operation *op : conversions)
      if (!op->use_empty() && llvm::all_of(op->getUsers(), llvm::IsaPred<DropOp>)) {
        for (Operation *drop : llvm::make_early_inc_range(op->getUsers()))
          drop->erase();
        dropped = true;
      }
    bool changed = false;
    (void)support::perform<NarrowFoldAction>(fn, [&] {
      (void)applyOpPatternsGreedily(
          conversions, FrozenRewritePatternSet(),
          GreedyRewriteConfig().setStrictness(GreedyRewriteStrictness::ExistingOps), &changed);
    });
    if (carried == 0 && narrowed == 0 && !dropped && !changed)
      markAllAnalysesPreserved();
  }
};

struct Narrow : idr::impl::IdrNarrowBase<Narrow> {
  using IdrNarrowBase::IdrNarrowBase;

  void runOnProgram(ProgramOp program) override {
    auto unsolved = [&] {
      program.emitError("internal error: idr-narrow: the range analysis failed");
      signalPassFailure();
    };
    FailureOr<std::reference_wrapper<const Ranges::Solved>> solved =
        getAnalysis<Ranges>().solved();
    if (failed(solved))
      return unsolved();
    uint64_t versioned = 0;
    {
      Facts facts(*solved);
      RewritePatternSet patterns(&getContext());
      populateVersionPatterns(patterns, facts, versioned);
      walkAndApplyPatterns(program, std::move(patterns));
    }
    // A versioned loop's copy holds values the first solve never saw, so
    // the program is solved again, the solve dropped with every analysis
    // the versions change: no declaration changes, and no symbol is added
    // or removed. Otherwise the first solve is the one the functions read.
    if (versioned != 0) {
      AnalysisManager::PreservedAnalyses kept;
      kept.preserve<TypeGraph, Layouts, SymbolTable>();
      getAnalysisManager().invalidate(kept);
      solved = getAnalysis<Ranges>().solved();
      if (failed(solved))
        return unsolved();
    }

    // The functions read the program's ranges from this pass's analysis
    // manager, which holds them through the nested run.
    OpPassManager nested(ProgramOp::getOperationName());
    nested.nest<FuncOp>().addPass(createIdrNarrowWords());
    if (failed(runPipeline(nested, program)))
      return signalPassFailure();
    numVersioned += versioned;
    // No declaration changes, and no symbol is added or removed.
    markAnalysesPreserved<TypeGraph, Layouts, SymbolTable>();
  }
};

} // namespace

} // namespace idr::narrow
