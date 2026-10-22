// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-narrow: the bigs and naturals integer range analysis proves fit a
// small become plain i64 words, and a loop whose natural only descends is
// versioned so that its copy proves it.
//
// The analysis is MLIR's, seeing our ops through their ranges, each
// function solved alone under the program's summaries (Ranges, an analysis
// of the program's analysis manager); this pass only reads it and
// rewrites. Nothing it learns is stored: the rewritten IR is the fact.
// Versioning runs on the program, since a versioned loop's copy holds
// values no summary saw, and the summaries are decided again after it; the
// word rewrite, idr-narrow-words, then runs on each function in parallel,
// each verified on its own, solving its function under the summaries it
// reads from the parent's cache. A narrowed op becomes `arith` on
// the values, which idr.big.to_int and the bigs made of integers convert
// where the web meets a big it does not prove; the pairs they form inside a
// web fold away, each by its own folder, in one walk.

#include "idr/Transforms/Narrow.h"

#include "idr/Analysis/Ranges.h"
#include "idr/Analysis/Solver/Work.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Effects/Whole.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Tail.h"
#include "idr/IR/Generated/Actions.h.inc"
#include "idr/Support/Actions.h"
#include "idr/Support/Footprint.h"
#include "idr/Support/Match.h"
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
#include "mlir/Rewrite/PatternApplicator.h"
#include "mlir/Transforms/FoldUtils.h"
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
  static constexpr std::string_view tag = ::idr::actions::narrowFold;
};

// The word rewrite of one function, solved under the summaries idr-narrow
// decided for the program and holds in its analysis manager while it runs
// this pass. Its work is its own solve's; the summaries' decide step is
// idr-narrow's, which ran it. Its word patterns are built once, before any
// function, and shared by every run, which reads its own facts through the
// rewriter it applies them with.
struct NarrowWords : idr::impl::IdrNarrowWordsBase<NarrowWords> {
  LogicalResult initialize(MLIRContext *ctx) override {
    RewritePatternSet patterns(ctx);
    populateWordPatterns(patterns);
    words = FrozenRewritePatternSet(std::move(patterns));
    return success();
  }

  void runOnProgram(ProgramOp program) {
    FuncOp fn = getOperation();
    // Only idr-narrow decides the program's summaries and holds them for
    // this pass: run without it, there is nothing to read.
    std::optional<std::reference_wrapper<Ranges>> ranges =
        getCachedParentAnalysis<Ranges>(program);
    if (!ranges) {
      fn.emitError("internal error: idr-narrow-words: no Ranges of the program");
      return signalPassFailure();
    }
    solver::Work work;
    FailureOr<std::unique_ptr<const Ranges::Solved>> solved = ranges->get().solve(fn, work);
    if (failed(solved)) {
      fn.emitError("internal error: idr-narrow-words: the range analysis failed");
      return signalPassFailure();
    }
    numWork += work.steps();
    Facts facts(fn, **solved);
    Decisions decided(facts.count());
    Changed changed = decideJoints(facts, decided);

    // One pass over the steps, in the walk's order: a joint's arguments
    // become words as it is entered, and a literal match on a big that fits
    // matches its word, so what runs inside reads them; its
    // results and what it passes as it is left, after everything inside;
    // every other op that takes or gives a big when it is reached, after
    // every op that gave it its operands.
    WordRewriter rewriter(&getContext(), facts, decided);
    PatternApplicator applicator(words);
    applicator.applyDefaultCostModel();
    for (const Step &step : facts.steps())
      match(
          step,
          [&](const Enter &in) {
            enter(rewriter, facts, decided, in);
            if (succeeded(applicator.matchAndRewrite(in.joint, rewriter)))
              changed = Changed::Yes;
          },
          [&](const Leave &out) { leave(rewriter, facts, decided, out); },
          [&](const Word &reached) {
            rewriter.step = &reached;
            if (succeeded(applicator.matchAndRewrite(reached.op, rewriter)))
              changed = Changed::Yes;
          });

    // A word made a big and back is the word, and a conversion of a
    // constant is its constant: each conversion is folded by its own
    // folder, then what no one reads is erased (a big made of an integer
    // and an integer read out of a big, each pure, the rewrite's own among
    // them: a versioned loop's start once its copy took the word, a big made
    // of a word that every reader now takes as the word, with each cast of
    // such a big into or out of a linear position; a big constant whose
    // readers now read its word, and the program's poison whose word was
    // taken), these ops and no other. What made a big says, through its
    // interface, never a list of ops.
    footprint::Vector<Operation *> conversions;
    auto conversion = [&](Operation *op) {
      if (!op)
        return false;
      Value result = op->getResult(0);
      if (isa<BigOfIntegerOpInterface>(op))
        return true;
      if (isa<BigToIntOp>(op))
        return true;
      if (isa<ub::PoisonOp>(op))
        return isBig(result.getType()) && decided.asked.test(facts.at(result));
      return isa<ConstantOp>(op) && isBig(result.getType());
    };
    fn.walk<WalkOrder::PreOrder>([&](Operation *op) {
      if (op->getNumResults() == 1 &&
          conversion(throughLinear(op->getResult(0)).getDefiningOp()))
        conversions.push_back(op);
    });
    // A conversion every reader of which now reads its word is made only to
    // be dropped: without its drops it is made for nothing, and erased.
    for (Operation *op : conversions)
      if (!op->use_empty() && llvm::all_of(op->getUsers(), llvm::IsaPred<CountDropOp>)) {
        for (Operation *drop : llvm::make_early_inc_range(op->getUsers()))
          drop->erase();
        changed = Changed::Yes;
      }
    // One walk forward folds each conversion, in the order the function
    // holds them, a producer before its readers, so that a reader's fold
    // sees its operand folded already; one walk back erases each that no
    // one reads, after its readers, so that a conversion whose every reader
    // went goes too. A fold that replaces its op erases it, and only it.
    (void)support::perform<NarrowFoldAction>(fn, [&] {
      OperationFolder folder(&getContext());
      footprint::Vector<Operation *> kept;
      for (Operation *op : conversions) {
        bool inPlace = false;
        if (succeeded(folder.tryToFold(op, &inPlace))) {
          changed = Changed::Yes;
          if (!inPlace)
            continue;
        }
        kept.push_back(op);
      }
      for (Operation *op : llvm::reverse(kept))
        if (op->use_empty() && effects::whole(op).onlyComputes()) {
          op->erase();
          changed = Changed::Yes;
        }
    });
    if (changed == Changed::No)
      return markAllAnalysesPreserved();
    // What follows a call may have changed: a count op or a conversion
    // after it gone. No web holding what a tail call gives was carried, so
    // what a call in tail position gives still goes straight to its tail;
    // each call's fact is decided again where it now stands.
    fn.walk([](CallOp call) { call.setTailKind(tail::decide(call)); });
  }

  FrozenRewritePatternSet words;
};

struct Narrow : idr::impl::IdrNarrowBase<Narrow> {
  using IdrNarrowBase::IdrNarrowBase;

  void runOnProgram(ProgramOp program) {
    uint64_t versioned = 0;
    // The pass's work: each decide step of the summaries it ran, and each
    // function's solve under them.
    solver::Work work;
    {
      // Each function's loops are versioned under its own solve, which the
      // program's summaries start.
      const Ranges &ranges = getAnalysis<Ranges>();
      work.add(ranges.work());
      for (FuncOp fn : program.getOps<FuncOp>()) {
        FailureOr<std::unique_ptr<const Ranges::Solved>> solved = ranges.solve(fn, work);
        if (failed(solved)) {
          fn.emitError("internal error: idr-narrow: the range analysis failed");
          return signalPassFailure();
        }
        RewritePatternSet patterns(&getContext());
        populateVersionPatterns(patterns, **solved, versioned);
        walkAndApplyPatterns(fn, std::move(patterns));
      }
    }
    // A versioned loop's copy holds values no summary saw, so the summaries
    // are decided again, dropped with every analysis the versions change: no
    // declaration changes, and no symbol is added or removed. Otherwise the
    // first summaries are the ones the functions read.
    if (versioned != 0) {
      AnalysisManager::PreservedAnalyses kept;
      kept.preserve<Layouts, SymbolTable>();
      getAnalysisManager().invalidate(kept);
      work.add(getAnalysis<Ranges>().work());
    }

    // The functions read the program's summaries from this pass's analysis
    // manager, which holds them through the nested run.
    OpPassManager nested(ProgramOp::getOperationName());
    nested.nest<FuncOp>().addPass(createIdrNarrowWords());
    if (failed(runPipeline(nested, program)))
      return signalPassFailure();
    numVersioned += versioned;
    numWork += work.steps();
    // No declaration changes, and no symbol is added or removed.
    markAnalysesPreserved<Layouts, SymbolTable>();
  }
};

} // namespace

} // namespace idr::narrow
