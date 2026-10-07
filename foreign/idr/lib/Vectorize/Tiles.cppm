// idr.vectorize:tiles: each linalg.generic with a parallel dimension (a loop over
// an array, Lower/Loops.cc) is tiled by the target's lanes along its
// parallel dimensions and by one along its reductions, its tile loop
// peeled so that the full tiles are known to be full, and each tile
// vectorized at those sizes: the full tiles without masks, the last one
// masked. Upstream's tiling, peeling and vectorizer do all of it; this pass
// decides the sizes, which is the one place the lane width reaches code:
// the target's vector register over the widest word the loop computes. A
// reduction dimension never gets more than one lane, so a floating
// accumulator adds in program order; that lane is a unit dimension of the
// tile's vectors (vector<4x1xf64>), which LLVM would take as four vectors
// of one, so the vector dialect's own patterns drop it again.
//
// Whether the vectorizer takes a generic is decided before anything
// changes. One it refuses (a call or a crash check in its body, a nested
// loop) stays as it is, for convert-linalg-to-loops, which runs its body in
// the program's order: tiled first and then refused, its tiles would run
// the body column by column within each group of rows, so a body that
// crashes or calls would do it in another order than the program's.
export module idr.vectorize:tiles;

import idr.mlir;
import idr.target;

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

// Whether the vectorizer takes the generic at these sizes, as its
// precondition says, the ops of the body included.
bool vectorizable(linalg::GenericOp op, ArrayRef<int64_t> sizes, ArrayRef<bool> scalable) {
  return succeeded(linalg::vectorizeOpPrecondition(op, sizes, scalable));
}


} // namespace

namespace idr::vectorize {

// What `vectorize` did with the loops it met: the loops vectorized, and the
// ones that stay scalar.
export struct Vectorized {
  uint64_t vectorized = 0;
  uint64_t scalar = 0;
};

// Vectorizes every loop of `module` the vectorizer takes, at the lanes of
// the target's vector register. Fails, after an error, when a tile of a
// loop the vectorizer takes does not vectorize.
export FailureOr<Vectorized> vectorize(ModuleOp module) {
  Vectorized done;
  MLIRContext *ctx = module.getContext();
  unsigned bits = idr::target::vectorBits(module);
  // As the walk meets them, each after the ops it holds: a generic in the
  // body of another comes before its holder and changes nothing outside
  // that body, and the holder, whose body holds that loop, stays scalar.
  // So no generic collected here is erased before its turn.
  SmallVector<linalg::GenericOp> generics;
  module.walk([&](linalg::GenericOp op) { generics.push_back(op); });
  IRRewriter rewriter(ctx);
  // What a vectorized tile is cleaned with: the unit dimensions of its
  // vectors dropped through shape casts, a read that broadcasts along the
  // lanes reduced to the read and a broadcast, the last tile's masked
  // region made the masked transfer it holds, and the vector dialect's
  // canonicalizations, which fold the casts and the broadcasts together.
  RewritePatternSet cleaning(ctx);
  vector::populateDropUnitDimWithShapeCastPatterns(cleaning);
  vector::populateVectorTransferPermutationMapLoweringPatterns(cleaning);
  vector::populateVectorMaskLoweringPatternsForSideEffectingOps(cleaning);
  for (RegisteredOperationName name : ctx->getRegisteredOperations())
    if (name.getDialectNamespace() == vector::VectorDialect::getDialectNamespace())
      name.getCanonicalizationPatterns(cleaning, ctx);
  FrozenRewritePatternSet clean(std::move(cleaning));
  // The functions holding a vectorized loop, cleaned once at the end: the
  // pattern driver takes an op isolated from above.
  SetVector<Operation *> touched;
  for (linalg::GenericOp op : generics) {
    if (!op.hasPureBufferSemantics())
      continue;
    SmallVector<utils::IteratorType> iterators = op.getIteratorTypesArray();
    if (llvm::none_of(iterators, linalg::isParallelIterator))
      continue;
    auto lanes = static_cast<int64_t>(std::max(1u, bits / widestWord(op)));
    SmallVector<int64_t> sizes;
    for (utils::IteratorType iterator : iterators)
      sizes.push_back(linalg::isParallelIterator(iterator) ? lanes : 1);
    // Fixed vectors: the lane count is the target's, not a runtime value.
    SmallVector<bool> scalable(sizes.size(), false);
    Location loc = op.getLoc();
    if (!vectorizable(op, sizes, scalable)) {
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
    touched.insert(outer->getParentWithTrait<OpTrait::IsIsolatedFromAbove>());
    remark::passed(loc, remark::RemarkOpts::name("Vectorized").category("idr-vectorize"))
        << ("the loop computes on " + Twine(lanes) + " lanes").str();
    ++done.vectorized;
  }
  for (Operation *function : touched)
    (void)applyPatternsGreedily(function, clean);
  return done;
}

} // namespace idr::vectorize
