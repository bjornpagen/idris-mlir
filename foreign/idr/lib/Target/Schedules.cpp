// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The schedule library: the transform script the vectorization group runs
// on each function, one copy for every target, built with the transform
// ops' own builders into the transform dialect's library module when the
// dialect loads; and the one transform op of ours it uses.
//
// The op exists because the transform dialect has no arithmetic on its
// params and its vectorize op takes one param per dimension: no script can
// divide the target's vector width by a loop's widest word, nor name the
// sizes of a loop of any rank. So the op decides the sizes, which is the one
// place the lane width reaches code, and does the tiling, peeling and
// vectorization at them with upstream's functions; the script chooses which
// ops it runs on and the patterns that clean what it made.
//
// Each loop over an array with a parallel dimension (a linalg.generic on
// buffers, as the lowering leaves it) computes on lanes along its last
// parallel dimension, the target's vector register over the widest word the
// loop computes, and one element along every other dimension: its tiles are
// then full in every dimension but that one, whose loop is peeled, so the
// full tiles read and write vectors without masks and only the last tile
// masks. A reduction dimension never gets more than one lane, so a floating
// accumulator adds in program order. Whether the vectorizer takes a loop is
// decided before anything changes: one it refuses (a call or a crash check in
// its body, a nested loop) stays, for convert-linalg-to-loops, which runs its
// body in the program's order; tiled first and then refused, its tiles would
// run the body in another order than the program's.

#include "idr/Target/Target.h"

#include "mlir/Dialect/Affine/IR/AffineOps.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Linalg/IR/Linalg.h"
#include "mlir/Dialect/Linalg/TransformOps/LinalgTransformOps.h"
#include "mlir/Dialect/Linalg/Transforms/Transforms.h"
#include "mlir/Dialect/Linalg/Utils/Utils.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/SCF/Transforms/TileUsingInterface.h"
#include "mlir/Dialect/SCF/Transforms/Transforms.h"
#include "mlir/Dialect/Transform/IR/TransformDialect.h"
#include "mlir/Dialect/Transform/IR/TransformOps.h"
#include "mlir/Dialect/Transform/IR/TransformTypes.h"
#include "mlir/Dialect/Transform/Interfaces/TransformInterfaces.h"
#include "mlir/Dialect/Utils/StaticValueUtils.h"
#include "mlir/Dialect/Vector/IR/VectorOps.h"
#include "mlir/Dialect/Vector/TransformOps/VectorTransformOps.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/DialectRegistry.h"
#include "mlir/IR/Location.h"
#include "mlir/IR/OpDefinition.h"
#include "mlir/IR/Remarks.h"
#include "mlir/IR/Verifier.h"
#include "mlir/Interfaces/DataLayoutInterfaces.h"
#include "mlir/Interfaces/FunctionInterfaces.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "mlir/Interfaces/TilingInterface.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/ADT/Twine.h"

#include <algorithm>
#include <cassert>
#include <cstdint>
#include <optional>
#include <string>
#include <utility>

#define GET_OP_CLASSES
#include "idr/Target/ScheduleOps.h.inc"

using namespace mlir;

namespace {

// The widest word the generic computes, in bits, as the module's data
// layout sizes it: its operands' elements and its body's values, the
// indices linalg.index gives among them, which the lowering makes words of
// the layout's index width. Every vector of a tile then fits one register.
unsigned widestWord(linalg::GenericOp op, const DataLayout &layout) {
  unsigned bits = 8;
  auto note = [&](Type type) {
    if (auto shaped = dyn_cast<ShapedType>(type))
      type = shaped.getElementType();
    if (type.isIntOrIndexOrFloat())
      bits = std::max(bits, static_cast<unsigned>(layout.getTypeSizeInBits(type).getFixedValue()));
  };
  for (Value operand : op->getOperands())
    note(operand.getType());
  op.getRegion().walk([&](Operation *inner) {
    for (Type type : inner->getResultTypes())
      note(type);
  });
  return bits;
}

// The width of the target's vector registers, as idr-target wrote it on
// the module, or nothing.
std::optional<std::int64_t> vectorWidth(Operation *op, const DataLayout &layout) {
  MLIRContext *ctx = op->getContext();
  std::optional<Attribute> width = layout.getDevicePropertyValue(
      StringAttr::get(ctx, idr::target::cpuDevice), StringAttr::get(ctx, idr::target::vectorWidthKey));
  auto bits = width ? dyn_cast<IntegerAttr>(*width) : IntegerAttr();
  if (!bits || bits.getInt() <= 0)
    return std::nullopt;
  return bits.getInt();
}

void scalar(Location loc, llvm::StringRef why) {
  remark::missed(loc, remark::RemarkOpts::name("Scalar").category("idr-lanes"))
      << ("the loop stays scalar: " + why).str();
}

// Computes `op` on lanes when the vectorizer takes it. Whether it did, or
// failure after an internal error.
FailureOr<bool> vectorizeLoop(RewriterBase &rewriter, linalg::GenericOp op) {
  if (!op.hasPureBufferSemantics() || op.getNumParallelLoops() == 0)
    return false;
  Location loc = op.getLoc();
  DataLayout layout = DataLayout::closest(op);
  std::optional<std::int64_t> width = vectorWidth(op, layout);
  if (!width) {
    op.emitError("internal error: the module states no max_vector_op_width for its CPU");
    return failure();
  }
  std::int64_t lanes = std::max<std::int64_t>(1, *width / widestWord(op, layout));
  SmallVector<utils::IteratorType> iterators = op.getIteratorTypesArray();
  unsigned laneDim = 0;
  for (auto [dim, iterator] : llvm::enumerate(iterators))
    if (linalg::isParallelIterator(iterator))
      laneDim = static_cast<unsigned>(dim);
  SmallVector<std::int64_t> sizes(iterators.size(), 1);
  sizes[laneDim] = lanes;
  // Fixed vectors: the lane count is the target's, not a runtime value.
  SmallVector<bool> scalable(sizes.size(), false);
  // What the vectorizer is asked before anything changes: the body, at
  // vectors no smaller than a static range, which a vector size must cover.
  SmallVector<std::int64_t> asked(sizes);
  for (auto [size, range] : llvm::zip_equal(asked, op.getStaticLoopRanges()))
    if (!ShapedType::isDynamic(range))
      size = std::max(size, range);
  if (failed(linalg::vectorizeOpPrecondition(op, asked, scalable))) {
    scalar(loc, "its body is not one the vectorizer takes");
    return false;
  }
  scf::SCFTilingOptions options;
  options.setTileSizes(getAsIndexOpFoldResult(op.getContext(), sizes));
  FailureOr<scf::SCFTilingResult> tiled =
      scf::tileUsingSCF(rewriter, cast<TilingInterface>(op.getOperation()), options);
  if (failed(tiled)) {
    scalar(loc, "it could not be tiled");
    return false;
  }
  // A loop for every dimension, every tile size being nonzero, outer to
  // inner in dimension order.
  if (tiled->loops.size() != sizes.size()) {
    op.emitError("internal error: tiling a loop of rank ")
        << sizes.size() << " made " << tiled->loops.size() << " loops";
    return failure();
  }
  rewriter.replaceOp(op, tiled->replacements);
  // The lane dimension's loop runs the full tiles, then its remainder runs
  // what is left: in the first every dynamic size is the tile's.
  auto full = cast<scf::ForOp>(tiled->loops[laneDim].getOperation());
  scf::ForOp last;
  (void)scf::peelForLoopAndSimplifyBounds(rewriter, full, last);
  for (auto [loop, whole] : {std::pair{full, true}, std::pair{last, false}}) {
    if (!loop)
      continue;
    SmallVector<linalg::GenericOp> tiles;
    loop.walk([&](linalg::GenericOp tile) { tiles.push_back(tile); });
    for (linalg::GenericOp tile : tiles) {
      FailureOr<linalg::VectorizationResult> vectorized =
          linalg::vectorize(rewriter, tile, sizes, scalable,
                            /*vectorizeNDExtract=*/false,
                            /*flatten1DDepthwiseConv=*/false,
                            /*assumeDynamicDimsMatchVecSizes=*/whole);
      // The loop was tiled because the vectorizer takes it: a tile it then
      // refuses is an error of this op, never a loop to leave scalar.
      if (failed(vectorized)) {
        tile.emitError("internal error: a tile of a loop the vectorizer takes did not vectorize");
        return failure();
      }
      // On buffers the generic has no results: the vector ops stand in.
      rewriter.replaceOp(tile, vectorized->replacements);
    }
  }
  remark::passed(loc, remark::RemarkOpts::name("Vectorized").category("idr-lanes"))
      << ("the loop computes on " + llvm::Twine(lanes) + " lanes").str();
  return true;
}

// The op on the transform dialect, with the dialects its rewrites make ops
// of loaded before it runs.
class ScheduleOps : public transform::TransformDialectExtension<ScheduleOps> {
public:
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(ScheduleOps)
  using Base::Base;

  void init() {
    declareDependentDialect<linalg::LinalgDialect>();
    declareGeneratedDialect<affine::AffineDialect>();
    declareGeneratedDialect<arith::ArithDialect>();
    declareGeneratedDialect<memref::MemRefDialect>();
    declareGeneratedDialect<scf::SCFDialect>();
    declareGeneratedDialect<vector::VectorDialect>();
    registerTransformOps<
#define GET_OP_LIST
#include "idr/Target/ScheduleOps.cpp.inc"
        >();
  }
};

// The library, built when the transform dialect loads, into its library
// module: once per context, read by every function's interpreter. Upstream's
// transform ops and this file's op are registered by then, their
// extensions coming first on the registry.
struct ScheduleLibrary : DialectExtension<ScheduleLibrary, transform::TransformDialect> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(ScheduleLibrary)

  void apply(MLIRContext *context, transform::TransformDialect *dialect) const final {
    ModuleOp library = dialect->getLibraryModule();
    auto builder = OpBuilder::atBlockEnd(library.getBody());
    // The schedule, under the name Target.h holds once, which is also its
    // location, for what the interpreter reports at its ops; on one handle it
    // only reads. The loops over arrays computed on lanes; then what the
    // vector dialect's conversion cannot take made what it can (the last
    // tile's masked region made the masked transfer it holds, a transfer
    // that permutes or broadcasts made a minor-identity one and a transpose
    // or broadcast), which must run to its end, since an op left would not
    // lower; then the unit dimensions vectorizing left dropped through shape
    // casts. Each runs upstream's patterns to their fixpoint, with no count
    // of rounds or rewrites, because each set's rewrites decrease a measure
    // no rewrite of the set increases: the lowering removes a mask region or
    // a permutation and makes none; the cleanup replaces an elementwise op, a
    // transpose or a loop's carried vector that has a fixed unit dimension by
    // one with those dimensions gone, which the set no longer matches, and
    // the shape casts it adds are none of the three.
    llvm::StringRef name = idr::target::vectorizeSchedule;
    auto schedule = transform::NamedSequenceOp::create(
        builder, NameLoc::get(StringAttr::get(context, name)), name,
        transform::AnyOpType::get(context), TypeRange(),
        [&](OpBuilder &b, Location loc, BlockArgument root) {
          llvm::StringRef generic = linalg::GenericOp::getOperationName();
          Value loops = transform::MatchOp::create(b, loc, root, generic);
          Value vectorized = idr::target::VectorizeLanesOp::create(
              b, loc, transform::AnyOpType::get(context), loops);
          transform::ApplyPatternsOp::create(b, loc, vectorized, [](OpBuilder &p, Location at) {
            transform::ApplyLowerMaskedTransfersPatternsOp::create(p, at);
            transform::ApplyTransferPermutationPatternsOp::create(p, at);
          });
          transform::ApplyPatternsOp::create(b, loc, vectorized, [](OpBuilder &p, Location at) {
            transform::ApplyDropUnitDimWithShapeCastPatternsOp::create(p, at);
          });
          transform::YieldOp::create(b, loc);
        });
    schedule.setArgAttr(0, transform::TransformDialect::kArgReadOnlyAttrName,
                        UnitAttr::get(context));
    // No pass runs on the library module, so nothing else verifies it: its
    // being well formed is this builder's invariant.
    assert(succeeded(mlir::verify(library)) && "the schedule library is well formed");
  }
};

} // namespace

#define GET_OP_CLASSES
#include "idr/Target/ScheduleOps.cpp.inc"

DiagnosedSilenceableFailure
idr::target::VectorizeLanesOp::apply(transform::TransformRewriter &rewriter,
                                     transform::TransformResults &results,
                                     transform::TransformState &state) {
  // Each function that now computes on lanes, once, in the order first
  // met: what the script cleans. The interpreter runs the script on one
  // function at a time, so the list holds one function at most and a search
  // of it is the whole of its dedup: no set of ops is kept.
  SmallVector<Operation *> vectorized;
  SmallVector<Operation *> targets = llvm::to_vector(state.getPayloadOps(getTarget()));
  for (Operation *target : targets) {
    auto loop = dyn_cast<linalg::GenericOp>(target);
    if (!loop)
      continue;
    auto function = loop->getParentOfType<FunctionOpInterface>();
    FailureOr<bool> done = vectorizeLoop(rewriter, loop);
    if (failed(done))
      return DiagnosedSilenceableFailure::definiteFailure();
    if (*done && function && !llvm::is_contained(vectorized, function.getOperation()))
      vectorized.push_back(function.getOperation());
  }
  results.set(cast<OpResult>(getVectorized()), vectorized);
  return DiagnosedSilenceableFailure::success();
}

void idr::target::VectorizeLanesOp::getEffects(
    SmallVectorImpl<MemoryEffects::EffectInstance> &effects) {
  transform::consumesHandle(getTargetMutable(), effects);
  transform::producesHandle(getOperation()->getOpResults(), effects);
  transform::modifiesPayload(effects);
}

void idr::target::registerScheduleLibrary(DialectRegistry &registry) {
  registry.addExtensions<ScheduleOps, ScheduleLibrary>();
}
