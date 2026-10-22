// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What the forms share: a region moved into the code that runs it, the
// sizes of a domain, and a read or a write at an index, of an element or of
// a cell, whose sizes are the cell's own.

#include "idr/Transforms/StructureLoops.h"

#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/Dialect/Utils/StaticValueUtils.h"
#include "llvm/ADT/SmallVectorExtras.h"

using namespace mlir;

namespace idr::structure {

namespace {

// The cell of `cellSizes` at `indices` of an array's leading dimensions.
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

SmallVector<Value> inlineRegion(RewriterBase &rewriter, Operation *op, ValueRange args,
                                TypeRange given) {
  Block &body = op->getRegion(0).front();
  Operation *end = body.getTerminator();
  rewriter.inlineBlockBefore(&body, rewriter.getInsertionBlock(), rewriter.getInsertionPoint(),
                             args);
  SmallVector<Value> values =
      isa<ArrayYieldOp>(end)
          ? SmallVector<Value>(cast<ArrayYieldOp>(end).getValues())
          : llvm::map_to_vector(given, [&](Type type) -> Value {
              return ub::PoisonOp::create(rewriter, end->getLoc(), type);
            });
  rewriter.eraseOp(end);
  return values;
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
