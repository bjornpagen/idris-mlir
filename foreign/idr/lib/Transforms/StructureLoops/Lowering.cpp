// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What the forms share: a region moved or copied into the code that runs
// it, a new array, and a read or a write at an index, of an element or of
// a cell, whose sizes are the cell's own.

#include "idr/Transforms/StructureLoops.h"

#include "mlir/Dialect/Arith/Utils/Utils.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/IRMapping.h"
#include "llvm/ADT/SmallVectorExtras.h"

using namespace mlir;

namespace idr::structure {

namespace {

// What the terminator `end` gives, each value as `mapping` maps it (an
// empty mapping keeps every value): its values, or nothing for
// ub.unreachable.
std::optional<SmallVector<Value>> givenBy(Operation *end, const IRMapping &mapping) {
  auto yield = dyn_cast<ArrayYieldOp>(end);
  if (!yield)
    return std::nullopt;
  return llvm::map_to_vector(yield.getValues(),
                             [&](Value value) { return mapping.lookupOrDefault(value); });
}

// The offsets, sizes and strides of the cell of `cellSizes` at `indices`.
struct Slice {
  SmallVector<OpFoldResult> offsets, sizes, strides;
};
Slice sliceAt(OpBuilder &b, ValueRange indices, ArrayRef<OpFoldResult> cellSizes) {
  Slice slice;
  for (Value index : indices) {
    slice.offsets.push_back(index);
    slice.sizes.push_back(b.getIndexAttr(1));
    slice.strides.push_back(b.getIndexAttr(1));
  }
  for (OpFoldResult size : cellSizes) {
    slice.offsets.push_back(b.getIndexAttr(0));
    slice.sizes.push_back(size);
    slice.strides.push_back(b.getIndexAttr(1));
  }
  return slice;
}

} // namespace

std::optional<SmallVector<Value>> inlineRegion(RewriterBase &rewriter, Operation *op,
                                               ValueRange args) {
  Block &body = op->getRegion(0).front();
  Operation *end = body.getTerminator();
  rewriter.inlineBlockBefore(&body, rewriter.getInsertionBlock(), rewriter.getInsertionPoint(),
                             args);
  std::optional<SmallVector<Value>> given = givenBy(end, IRMapping());
  rewriter.eraseOp(end);
  return given;
}

std::optional<SmallVector<Value>> cloneRegion(OpBuilder &b, Operation *op, ValueRange args) {
  Block &body = op->getRegion(0).front();
  IRMapping mapping;
  mapping.map(body.getArguments(), args);
  for (Operation &inner : body.without_terminator())
    b.clone(inner, mapping);
  return givenBy(body.getTerminator(), mapping);
}

SmallVector<OpFoldResult> extentsOf(OpBuilder &b, Operation *op, unsigned dims) {
  auto generating = cast<GeneratingOpInterface>(op);
  return llvm::map_to_vector(llvm::seq(0u, dims),
                             [&](unsigned d) { return generating.getExtent(b, d); });
}

SmallVector<Value> valuesOf(OpBuilder &b, Location loc, ArrayRef<OpFoldResult> sizes) {
  return llvm::map_to_vector(
      sizes, [&](OpFoldResult size) { return getValueOrCreateConstantIndexOp(b, loc, size); });
}

Value emptyOf(OpBuilder &b, Location loc, RankedTensorType type, ArrayRef<OpFoldResult> dims) {
  SmallVector<Value> dynamic;
  for (auto [d, size] : llvm::enumerate(dims))
    if (type.isDynamicDim(static_cast<unsigned>(d)))
      dynamic.push_back(getValueOrCreateConstantIndexOp(b, loc, size));
  return tensor::EmptyOp::create(b, loc, type, dynamic);
}

Value readCell(OpBuilder &b, Location loc, Value array, ValueRange indices, Type cell) {
  auto shaped = dyn_cast<RankedTensorType>(cell);
  if (!shaped)
    return tensor::ExtractOp::create(b, loc, array, indices);
  if (indices.empty())
    return array;
  SmallVector<OpFoldResult> sizes = tensor::getMixedSizes(b, loc, array);
  Slice slice = sliceAt(b, indices, ArrayRef(sizes).drop_front(indices.size()));
  return tensor::ExtractSliceOp::create(b, loc, shaped, array, slice.offsets, slice.sizes,
                                        slice.strides);
}

Value writeCell(OpBuilder &b, Location loc, Value cell, Value array, ValueRange indices) {
  if (!isa<RankedTensorType>(cell.getType()))
    return tensor::InsertOp::create(b, loc, cell, array, indices);
  if (indices.empty())
    return cell;
  Slice slice = sliceAt(b, indices, tensor::getMixedSizes(b, loc, cell));
  return tensor::InsertSliceOp::create(b, loc, cell, array, slice.offsets, slice.sizes,
                                       slice.strides);
}

} // namespace idr::structure
