// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-vectorize: each linalg.generic with a parallel dimension (a loop over
// an array, as idr-lower leaves it) is tiled by the target's lanes along its
// parallel dimensions and by one along its reductions, its tile loop peeled
// so that the full tiles are known to be full, and each tile vectorized at
// those sizes: the full tiles without masks, the last one masked. Upstream's
// tiling, peeling and vectorizer do all of it; this pass decides the sizes,
// which is the one place the lane width reaches code: the target's vector
// register over the widest word the loop computes. A reduction dimension
// never gets more than one lane, so a floating accumulator adds in program
// order; that lane is a unit dimension of the tile's vectors
// (vector<4x1xf64>), which LLVM would take as four vectors of one, so the
// vector dialect's own patterns drop it again.
//
// Whether the vectorizer takes a generic is decided before anything
// changes. One it refuses (a call or a crash check in its body, a nested
// loop) stays as it is, for convert-linalg-to-loops, which runs its body in
// the program's order: tiled first and then refused, its tiles would run
// the body column by column within each group of rows, so a body that
// crashes or calls would do it in another order than the program's.
//
// One function at a time: of its module the pass reads only the target.

#include "idr/Transforms/Vectorize.h"

#include "idr/Target/Target.h"

#include "mlir/Dialect/Affine/IR/AffineOps.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/Linalg/IR/Linalg.h"
#include "mlir/Dialect/Linalg/Transforms/Transforms.h"
#include "mlir/Dialect/Linalg/Utils/Utils.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/SCF/Transforms/TileUsingInterface.h"
#include "mlir/Dialect/SCF/Transforms/Transforms.h"
#include "mlir/Dialect/Vector/IR/VectorOps.h"
#include "mlir/Dialect/Vector/Transforms/LoweringPatterns.h"
#include "mlir/Dialect/Vector/Transforms/VectorRewritePatterns.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/Remarks.h"
#include "mlir/Interfaces/TilingInterface.h"
#include "mlir/Rewrite/FrozenRewritePatternSet.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"

#include <memory>

namespace idr {
#define GEN_PASS_DEF_IDRVECTORIZE
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace {

// The widest word the generic computes, in bits: its operands' elements
// and its body's values, so that every vector of the tile fits one register.
unsigned widestWord(linalg::GenericOp op) {
  unsigned bits = 8;
  auto note = [&](Type type) {
    if (auto shaped = dyn_cast<ShapedType>(type))
      type = shaped.getElementType();
    if (type.isIntOrFloat())
      bits = std::max(bits, type.getIntOrFloatBitWidth());
  };
  for (Value operand : op->getOperands())
    note(operand.getType());
  op.getRegion().walk([&](Operation *inner) {
    for (Type type : inner->getResultTypes())
      note(type);
  });
  return bits;
}

// The loops `vectorize` vectorized, and the ones that stay scalar.
struct Vectorized {
  uint64_t vectorized = 0;
  uint64_t scalar = 0;
};

// Vectorizes every loop of `fn` the vectorizer takes, at the lanes of a
// vector register of `bits`, and cleans the tiles with `clean`. Fails,
// after an error, when a tile of a loop the vectorizer takes does not
// vectorize.
FailureOr<Vectorized> vectorize(func::FuncOp fn, unsigned bits,
                                const FrozenRewritePatternSet &clean) {
  Vectorized done;
  MLIRContext *ctx = fn.getContext();
  // As the walk meets them, each after the ops it holds: a generic in the
  // body of another comes before its holder and changes nothing outside
  // that body, and the holder, whose body holds that loop, stays scalar.
  // So no generic collected here is erased before its turn.
  SmallVector<linalg::GenericOp> generics;
  fn.walk([&](linalg::GenericOp op) { generics.push_back(op); });
  IRRewriter rewriter(ctx);
  for (linalg::GenericOp op : generics) {
    if (!op.hasPureBufferSemantics() || op.getNumParallelLoops() == 0)
      continue;
    auto lanes = static_cast<int64_t>(std::max(1u, bits / widestWord(op)));
    SmallVector<int64_t> sizes;
    for (utils::IteratorType iterator : op.getIteratorTypesArray())
      sizes.push_back(linalg::isParallelIterator(iterator) ? lanes : 1);
    // Fixed vectors: the lane count is the target's, not a runtime value.
    SmallVector<bool> scalable(sizes.size(), false);
    Location loc = op.getLoc();
    // The vectorizer's precondition covers the ops of the body too.
    if (failed(linalg::vectorizeOpPrecondition(op, sizes, scalable))) {
      remark::missed(loc, remark::RemarkOpts::name("Scalar").category("idr-vectorize"))
          << "the loop stays scalar: its body is not one the vectorizer takes";
      ++done.scalar;
      continue;
    }
    scf::SCFTilingOptions options;
    SmallVector<OpFoldResult> tiles;
    for (int64_t size : sizes)
      tiles.push_back(rewriter.getIndexAttr(size));
    options.setTileSizes(tiles);
    FailureOr<scf::SCFTilingResult> tiled =
        scf::tileUsingSCF(rewriter, cast<TilingInterface>(op.getOperation()), options);
    if (failed(tiled) || tiled->loops.empty()) {
      remark::missed(loc, remark::RemarkOpts::name("Scalar").category("idr-vectorize"))
          << "the loop stays scalar: it could not be tiled";
      ++done.scalar;
      continue;
    }
    rewriter.replaceOp(op, tiled->replacements);
    // The outermost tile loop runs the full tiles, then the last one
    // runs what is left: every dynamic size in the first is the tile.
    auto outer = cast<scf::ForOp>(tiled->loops.front().getOperation());
    scf::ForOp last;
    (void)scf::peelForLoopAndSimplifyBounds(rewriter, outer, last);
    for (auto [loop, full] : {std::pair{outer, true}, std::pair{last, false}}) {
      if (!loop)
        continue;
      SmallVector<linalg::GenericOp> inner;
      loop.walk([&](linalg::GenericOp tile) { inner.push_back(tile); });
      for (linalg::GenericOp tile : inner) {
        FailureOr<linalg::VectorizationResult> vectorized =
            linalg::vectorize(rewriter, tile, sizes, scalable,
                              /*vectorizeNDExtract=*/false,
                              /*flatten1DDepthwiseConv=*/false,
                              /*assumeDynamicDimsMatchVecSizes=*/full);
        // The loop was tiled because the vectorizer takes it: a tile it
        // then refuses is this pass's error, never a loop to leave scalar.
        if (failed(vectorized)) {
          tile.emitError("internal error: idr-vectorize: a tile of a loop the vectorizer "
                         "takes did not vectorize");
          return failure();
        }
        // On buffers the generic has no results: the vector ops stand in.
        rewriter.replaceOp(tile, vectorized->replacements);
      }
    }
    remark::passed(loc, remark::RemarkOpts::name("Vectorized").category("idr-vectorize"))
        << ("the loop computes on " + Twine(lanes) + " lanes").str();
    ++done.vectorized;
  }
  if (done.vectorized != 0)
    (void)applyPatternsGreedily(fn.getOperation(), clean);
  return done;
}

struct Vectorize : idr::impl::IdrVectorizeBase<Vectorize> {
  using IdrVectorizeBase::IdrVectorizeBase;

  // What the vectorized tiles are cleaned with: the unit dimensions of
  // their vectors dropped through shape casts, a read that broadcasts along
  // the lanes reduced to the read and a broadcast, the last tile's masked
  // region made the masked transfer it holds, and the vector dialect's
  // canonicalizations, which fold the casts and the broadcasts together.
  // Built once, as the canonicalizer builds its own, and shared by the
  // pass's copies on every thread.
  LogicalResult initialize(MLIRContext *ctx) override {
    RewritePatternSet cleaning(ctx);
    vector::populateDropUnitDimWithShapeCastPatterns(cleaning);
    vector::populateVectorTransferPermutationMapLoweringPatterns(cleaning);
    vector::populateVectorMaskLoweringPatternsForSideEffectingOps(cleaning);
    for (RegisteredOperationName name :
         ctx->getRegisteredOperationsByDialect(vector::VectorDialect::getDialectNamespace()))
      name.getCanonicalizationPatterns(cleaning, ctx);
    clean = std::make_shared<FrozenRewritePatternSet>(std::move(cleaning));
    return success();
  }

  void runOnOperation() override {
    func::FuncOp fn = getOperation();
    unsigned bits = idr::target::vectorBits(fn->getParentOfType<ModuleOp>());
    FailureOr<Vectorized> done = vectorize(fn, bits, *clean);
    if (failed(done))
      return signalPassFailure();
    numVectorized += done->vectorized;
    numScalar += done->scalar;
    if (done->vectorized == 0)
      markAllAnalysesPreserved();
  }

  std::shared_ptr<const FrozenRewritePatternSet> clean;
};

} // namespace
