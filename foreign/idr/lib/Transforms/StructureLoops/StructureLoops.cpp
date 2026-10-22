// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-structure-loops: each op of the generating set whose region only
// computes over words made linalg, once, in one walk. The walk visits an op
// after the ops inside its region, so an op is decided with what its region
// holds already made; nothing is visited twice. An op that stays is left to
// idr-ordered-loops.
//
// idr-ordered-loops: each op of the generating set left, which bufferization
// has put on buffers, made its loops by upstream's lowerToLoopsUsingSCFForOp
// from its own tiling methods, in row-major order, the inner ops first, so
// that the step an outer op's loops clone holds loops already.

#include "idr/Transforms/StructureLoops.h"

#include "idr/Transforms/Pipeline.h"

#include "mlir/Dialect/SCF/Transforms/TileUsingInterface.h"
#include "mlir/Transforms/WalkPatternRewriteDriver.h"

namespace idr {
#define GEN_PASS_DEF_IDRSTRUCTURELOOPS
#define GEN_PASS_DEF_IDRORDEREDLOOPS
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace idr::structure {

namespace {

// How many ops took each form, the statistics of the pass: an interchange
// keeps its frame parallel, so it counts with the parallel forms.
struct Counts {
  Statistic &parallel;
  Statistic &reductions;
  Statistic &ordered;
};

// A tabulation is parallel or stays.
struct TabulateForm : OpRewritePattern<ArrayTabulateOp> {
  TabulateForm(MLIRContext *ctx, Counts &counts) : OpRewritePattern(ctx), counts(counts) {}
  LogicalResult matchAndRewrite(ArrayTabulateOp op, PatternRewriter &rewriter) const override {
    if (formOf(op) == Form::Ordered) {
      ++counts.ordered;
      return rewriter.notifyMatchFailure(op, "stays for its loops");
    }
    lowerParallel(rewriter, op);
    ++counts.parallel;
    return success();
  }
  Counts &counts;
};

// A fold is a reduction, an interchange, or stays.
struct FoldForm : OpRewritePattern<ArrayFoldLastOp> {
  FoldForm(MLIRContext *ctx, Counts &counts) : OpRewritePattern(ctx), counts(counts) {}
  LogicalResult matchAndRewrite(ArrayFoldLastOp op, PatternRewriter &rewriter) const override {
    switch (formOf(op)) {
    case Form::Reduction:
      lowerReduction(rewriter, op);
      ++counts.reductions;
      return success();
    // A fold's last dimension is ordered by its iterator types, so no fold
    // is parallel throughout: its parallel frame is an interchange's.
    case Form::Interchange:
    case Form::Parallel:
      lowerInterchange(rewriter, op);
      ++counts.parallel;
      return success();
    case Form::Ordered:
      ++counts.ordered;
      return rewriter.notifyMatchFailure(op, "stays for its loops");
    }
    return failure();
  }
  Counts &counts;
};

// A scan, which keeps every step, is an interchange or stays.
struct ScanForm : OpRewritePattern<ArrayScanLastOp> {
  ScanForm(MLIRContext *ctx, Counts &counts) : OpRewritePattern(ctx), counts(counts) {}
  LogicalResult matchAndRewrite(ArrayScanLastOp op, PatternRewriter &rewriter) const override {
    if (formOf(op) == Form::Ordered) {
      ++counts.ordered;
      return rewriter.notifyMatchFailure(op, "stays for its loops");
    }
    lowerInterchange(rewriter, op);
    ++counts.parallel;
    return success();
  }
  Counts &counts;
};

struct StructureLoops : idr::impl::IdrStructureLoopsBase<StructureLoops> {
  void runOnProgram(ProgramOp) {
    Counts counts{numParallel, numReductions, numOrdered};
    RewritePatternSet patterns(&getContext());
    patterns.add<TabulateForm, FoldForm, ScanForm>(&getContext(), counts);
    walkAndApplyPatterns(getOperation(), std::move(patterns));
  }
};

// An op of the generating set, on buffers, made its loops, which take its
// place.
struct Loops : OpInterfaceRewritePattern<DestinationStyleOpInterface> {
  using OpInterfaceRewritePattern::OpInterfaceRewritePattern;
  LogicalResult matchAndRewrite(DestinationStyleOpInterface op,
                                PatternRewriter &rewriter) const override {
    if (!arrays::isGenerating(op))
      return rewriter.notifyMatchFailure(op, "writes its destinations by no region of ours");
    rewriter.setInsertionPoint(op);
    if (failed(scf::lowerToLoopsUsingSCFForOp(rewriter, cast<TilingInterface>(op.getOperation()))))
      return op->emitOpError("internal error: idr-ordered-loops: left on tensors");
    rewriter.eraseOp(op);
    return success();
  }
};

struct OrderedLoops : idr::impl::IdrOrderedLoopsBase<OrderedLoops> {
  void runOnProgram(ProgramOp) {
    RewritePatternSet patterns(&getContext());
    patterns.add<Loops>(&getContext());
    walkAndApplyPatterns(getOperation(), std::move(patterns));
  }
};

} // namespace

} // namespace idr::structure
