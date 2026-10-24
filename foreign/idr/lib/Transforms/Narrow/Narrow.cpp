// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-narrow: the bigs and naturals integer range analysis proves fit a
// small become plain i64 words, and a loop whose natural only descends is
// versioned so that its copy proves it.
//
// The analysis is MLIR's, seeing our ops through their ranges, each
// function solved alone under the program's summaries, and the bounds of
// its values read off its one solve under the final ones (Ranges, an
// analysis of the program's analysis manager): idr-narrow decides it, and
// idr-narrow-words, on each function in parallel, each verified on its
// own, reads its function's bounds from the parent's cache and rewrites.
// Nothing it learns is stored: the rewritten IR is the fact. A loop's
// version is its function's own rewrite: its two copies start inside what
// the loop started from, so what the function passes and returns stays
// inside the summaries, and only a function with a version is solved
// again, under them, for the values its copies hold. A narrowed op becomes
// `arith` on the values, which idr.big.to_int and the bigs made of integers
// convert where the web meets a big it does not prove; the pairs they form
// inside a web fold away, each by its own folder, in one walk.

#include "idr/Transforms/Narrow.h"

#include "idr/Analysis/Ranges.h"
#include "idr/Analysis/Solver/Decision.h"
#include "idr/Analysis/Solver/Work.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Effects/Whole.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Generated/Actions.h.inc"
#include "idr/IR/Generated/ApplyGroups.h.inc"
#include "idr/Support/Actions.h"
#include "idr/Support/Footprint.h"
#include "idr/Support/Match.h"
#include "idr/Transforms/Optimize/Tails.h"
#include "idr/Transforms/Pipeline.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Rewrite/FrozenRewritePatternSet.h"
#include "mlir/Rewrite/PatternApplicator.h"
#include "mlir/Transforms/FoldUtils.h"
#include "mlir/Transforms/WalkPatternRewriteDriver.h"

#include "llvm/ADT/SmallVector.h"

#define GEN_PASS_DEF_IDRNARROW
#define GEN_PASS_DEF_IDRNARROWWORDS
#include "idr/IR/Generated/PassDialects.h.inc"

namespace idr {
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

// The versions and the word rewrite of one function, under the bounds
// idr-narrow decided for the program and holds in its analysis manager
// while it runs this pass. Its work is the solve of a function it gave a
// version; the summaries' decide step is idr-narrow's, which ran it. Its
// word patterns are built once, before any function, and shared by every
// run, which reads its own facts through the rewriter it applies them with.
struct NarrowWords : idr::impl::IdrNarrowWordsBase<NarrowWords> {
  LogicalResult initialize(MLIRContext *ctx) override {
    RewritePatternSet patterns(ctx);
    populateWordPatterns(patterns);
    words = FrozenRewritePatternSet(std::move(patterns));
    return success();
  }

  void runOnProgram(ProgramOp program) {
    FuncOp fn = getOperation();
    // Only idr-narrow decides the program's summaries and the bounds of
    // each function's values, and holds them for this pass.
    const Ranges &ranges = solver::decided(getCachedParentAnalysis<Ranges>(program));
    // Each loop whose natural only descends is versioned under the bounds
    // of the function's one solve. A version's copies hold values no solve
    // saw, so a function with one is solved again under the summaries,
    // which still hold.
    Bounded solved(fn, ranges.boundsOf(fn));
    uint64_t versioned = 0;
    RewritePatternSet versions(&getContext());
    populateVersionPatterns(versions, solved, versioned);
    walkAndApplyPatterns(fn, std::move(versions));
    Changed changed = versioned == 0 ? Changed::No : Changed::Yes;
    solver::Work work;
    footprint::Vector<ranges::Bounds> rewritten;
    if (changed == Changed::Yes)
      rewritten = ranges.boundsOfRewritten(fn, work);
    numVersioned += versioned;
    numWork += work.steps();
    Facts facts = changed == Changed::No ? Facts(fn, std::move(solved))
                                         : Facts(fn, Bounded(fn, rewritten));
    Decisions decided(facts.count());
    changed |= decideJoints(facts, decided);

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
    // Every op the walk rewrites has taken its smalls' words; a use left
    // that takes over what a value its count frees holds is given the small
    // at the type of the big it stood for.
    giveSmalls(rewriter);

    // A word made a big and back is the word, and a conversion of a
    // constant is its constant: each conversion is folded by its own
    // folder, then what no one reads is erased (a big made of an integer
    // and an integer read out of a big, each pure, the rewrite's own among
    // them: a versioned loop's start once its copy took the word, a big made
    // of a word that every reader now takes as the word, with each cast of
    // such a big into or out of a linear position; a big constant whose
    // readers now read its word, the program's poison among them), these
    // ops and no other. A conversion between a big and its word says so,
    // either way, through its interface; a big constant through its trait.
    // Essential, two things with no meaning in common: a constant is no
    // conversion.
    footprint::Vector<Operation *> conversions;
    auto conversion = [&](Operation *op) {
      if (!op)
        return false;
      if (isa<BigWordOpInterface>(op))
        return true;
      return op->hasTrait<OpTrait::ConstantLike>() &&
             isCarriedAsBig(op->getResult(0).getType());
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
    // What follows a call may have changed: a loop versioned, a count op or
    // a conversion after it gone. No web holding what a tail call gives was
    // carried, so what a call in tail position gives still goes straight to
    // its tail; every call takes its fact again from the function's tails.
    (void)optimize::decideTails(fn);
  }

  FrozenRewritePatternSet words;
};

struct Narrow : idr::impl::IdrNarrowBase<Narrow> {
  using IdrNarrowBase::IdrNarrowBase;

  void runOnProgram(ProgramOp program) {
    // The pass's work: the solves of the summaries and the bounds, decided
    // once.
    numWork += getAnalysis<Ranges>().work();
    // The functions read the program's bounds from this pass's analysis
    // manager, which holds them through the nested run. Which passes run
    // there is the pipeline's to say: its list pairs this decide step with
    // its apply group.
    OpPassManager nested(ProgramOp::getOperationName());
    ::idr::pipeline::applyGroupOfIdrNarrow(nested);
    if (failed(runPipeline(nested, program)))
      return signalPassFailure();
    // No declaration changes, and no symbol is added or removed.
    markAnalysesPreserved<Layouts, SymbolTable>();
  }
};

} // namespace

} // namespace idr::narrow
