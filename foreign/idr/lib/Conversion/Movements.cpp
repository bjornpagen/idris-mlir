// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The four movements a step of a generating op, or an update split around
// a call, makes in its buffers (take, copy, place, put back), and the copy
// placed in a buffer allocated for it. Each moves what the slots under its
// indices hold: an element, at its place (Elements.h), or a cell's
// elements one by one, in row-major order.
//
// A take moves out what the slots hold, leaving their place to be put
// back into; a copy reads it with references of its own, the slots keeping
// theirs; a place puts a value where the slots hold nothing, so it
// releases nothing; a put-back puts one in the place a take left. A copy
// placed in a buffer allocated for it releases nothing either: its
// target's slots were never written.

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/Conversion/Arrays.h"
#include "idr/Conversion/Elements.h"
#include "idr/Conversion/IdrPattern.h"
#include "idr/Conversion/Runtime.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Transforms/DialectConversion.h"

#include <cstdint>
#include <type_traits>

using namespace mlir;

namespace idr::conversion {

namespace {

// How a move out leaves the slots it reads: their place left to be put
// back into (take), or keeping their references, the value gaining its own
// (copy).
enum class Out : std::uint8_t { Take, Copy };

// Where an element goes: slots that hold nothing (a fresh cell's, a
// destination's), or the place a take left (a put-back).
enum class Into : std::uint8_t { Empty, Taken };

// Puts `value` at `address` as `into` says.
void putAt(OpBuilder &b, Location loc, Runtime &runtime, Into into, Value address,
           const layout::Element &element, ValueRange value) {
  if (into == Into::Taken)
    putIn(b, loc, runtime, address, element, value);
  else
    placeElement(b, loc, runtime, address, element, value);
}

// The element at `from`, read with a reference of its own, its slots
// keeping theirs, put at `to` as `into` says; `type` the element's.
void copyElement(OpBuilder &b, Location loc, Runtime &runtime, const Layouts &layouts, Into into,
                 Value from, Value to, const layout::Element &element, Type type) {
  SmallVector<Value> value = readElement(b, loc, runtime, from, element);
  putAt(b, loc, runtime, into, to, element, value);
  runtime.inc(b, loc, layouts.components(type), value);
}

// The cell under `lead` leading indices of a buffer of `type`,
// `components` its runtime form: its extents, the buffer's trailing ones.
struct CellOf {
  SmallVector<OpFoldResult> sizes;
};
CellOf cellOf(OpBuilder &b, Location loc, MemRefType type, ValueRange components,
              size_t lead) {
  Descriptor d = unpack(b, loc, type, components);
  return {SmallVector<OpFoldResult>(ArrayRef(d.sizes).drop_front(lead))};
}

// Each element of a cell of `sizes`, its index within the cell given to
// `each` inside a loop nest in row-major order.
template <typename Each>
  requires std::is_invocable_v<Each, OpBuilder &, ValueRange>
void forEachElement(OpBuilder &b, Location loc, ArrayRef<OpFoldResult> sizes, Each &&each) {
  SmallVector<Value> lower, upper, steps;
  for (OpFoldResult size : sizes) {
    lower.push_back(arith::ConstantIndexOp::create(b, loc, 0));
    upper.push_back(asIndex(b, loc, size));
    steps.push_back(arith::ConstantIndexOp::create(b, loc, 1));
  }
  scf::buildLoopNest(b, loc, lower, upper, steps,
                     [&](OpBuilder &at, Location, ValueRange ivs) { each(at, ivs); });
}

// A fresh cell of `cellType` with the extents `sizes`: the runtime's cell,
// and each dynamic extent.
SmallVector<Value> freshCell(OpBuilder &b, Location loc, Runtime &runtime, MemRefType cellType,
                             ArrayRef<OpFoldResult> sizes, const layout::Element &element) {
  Value cell = newCell(b, loc, runtime, countOf(b, loc, sizes), element);
  Descriptor d{cell, b.getI64IntegerAttr(0), SmallVector<OpFoldResult>(sizes), {}};
  return pack(b, loc, cellType, d);
}

// A take or a copy: what the slots under the op's indices hold, an element
// or a fresh cell of the elements under them. A take moves each element
// out of a box with no test where the buffer's grade claims its boxes
// unshared (boxSharingOf), in mutable memory or a value array's buffer.
template <typename OpT, Out out>
struct LowerMoveOut : IdrPattern<OpT> {
  using IdrPattern<OpT>::IdrPattern;
  LogicalResult matchAndRewrite(OpT op, typename IdrPattern<OpT>::OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    auto type = cast<MemRefType>(unrestricted(op.getBuffer().getType()));
    Type elementType = type.getElementType();
    layout::Element element = this->layouts.element(elementType);
    SmallVector<Value> indices = indicesOf(adaptor.getIndices());
    // What one element moves out as, `from` its address.
    auto moved = [&](OpBuilder &b, Value from) -> SmallVector<Value> {
      if constexpr (out == Out::Take) {
        return takeOut(b, loc, this->runtime, this->layouts, from, element, elementType,
                       boxSharingOf(op.getBuffer().getType()));
      } else {
        SmallVector<Value> value = readElement(b, loc, this->runtime, from, element);
        this->runtime.inc(b, loc, this->layouts.components(elementType), value);
        return value;
      }
    };
    auto cellType = dyn_cast<MemRefType>(unrestricted(op.getValue().getType()));
    if (!cellType) {
      Value from = elementAddress(rewriter, loc, this->runtime, type, adaptor.getBuffer(), element,
                                  indices);
      rewriter.replaceOpWithMultiple(op, {moved(rewriter, from)});
      return success();
    }
    CellOf cell = cellOf(rewriter, loc, type, adaptor.getBuffer(), indices.size());
    SmallVector<Value> made =
        freshCell(rewriter, loc, this->runtime, cellType, cell.sizes, element);
    forEachElement(rewriter, loc, cell.sizes, [&](OpBuilder &b, ValueRange ivs) {
      SmallVector<Value> at(indices);
      llvm::append_range(at, ivs);
      Value from = elementAddress(b, loc, this->runtime, type, adaptor.getBuffer(), element, at);
      Value to = elementAddress(b, loc, this->runtime, cellType, made, element, ivs);
      placeElement(b, loc, this->runtime, to, element, moved(b, from));
    });
    rewriter.replaceOpWithMultiple(op, {made});
    return success();
  }
};

// A place or a put-back: the value into the slots under the op's indices,
// which hold nothing, or the place a take left. A cell's elements are
// copied in, each with a reference of its own, and the cell's own
// reference is given up: whether another value shares the cell is known
// only at run time, from its count, and a cell no one else holds is freed,
// its elements losing the references the copy gave them back.
template <typename OpT, Into into>
struct LowerMoveIn : IdrPattern<OpT> {
  using IdrPattern<OpT>::IdrPattern;
  LogicalResult matchAndRewrite(OpT op, typename IdrPattern<OpT>::OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    auto type = cast<MemRefType>(unrestricted(op.getBuffer().getType()));
    Type elementType = type.getElementType();
    layout::Element element = this->layouts.element(elementType);
    SmallVector<Value> indices = indicesOf(adaptor.getIndices());
    auto cellType = dyn_cast<MemRefType>(unrestricted(op.getValue().getType()));
    if (!cellType) {
      Value to = elementAddress(rewriter, loc, this->runtime, type, adaptor.getBuffer(), element,
                                indices);
      putAt(rewriter, loc, this->runtime, into, to, element, adaptor.getValue());
      rewriter.eraseOp(op);
      return success();
    }
    ValueRange value = adaptor.getValue();
    CellOf cell = cellOf(rewriter, loc, cellType, value, 0);
    forEachElement(rewriter, loc, cell.sizes, [&](OpBuilder &b, ValueRange ivs) {
      SmallVector<Value> at(indices);
      llvm::append_range(at, ivs);
      Value from = elementAddress(b, loc, this->runtime, cellType, value, element, ivs);
      Value to = elementAddress(b, loc, this->runtime, type, adaptor.getBuffer(), element, at);
      copyElement(b, loc, this->runtime, this->layouts, into, from, to, element, elementType);
    });
    this->runtime.dec(rewriter, loc, layout::Word::Cell, value.front());
    rewriter.eraseOp(op);
    return success();
  }
};

// A copy placed in a buffer allocated for it: each element of the source
// moved into the target's slot at its index, which holds nothing, with a
// reference of its own; the source keeps its own, and nothing is released.
// A copy of words is upstream's copy: a slot of words holds nothing to
// release, so placing it and writing over it are one write.
struct LowerArrayPlaceCopy : IdrPattern<ArrayPlaceCopyOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(ArrayPlaceCopyOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    auto from = cast<MemRefType>(op.getSource().getType());
    auto to = cast<MemRefType>(op.getTarget().getType());
    Type elementType = from.getElementType();
    layout::Element element = layouts.element(elementType);
    if (llvm::none_of(element.slots, [](const layout::Slot &slot) { return slot.counted(); })) {
      rewriter.replaceOpWithNewOp<memref::CopyOp>(op, op.getSource(), op.getTarget());
      return success();
    }
    CellOf cell = cellOf(rewriter, loc, to, adaptor.getTarget(), 0);
    forEachElement(rewriter, loc, cell.sizes, [&](OpBuilder &b, ValueRange ivs) {
      Value at = elementAddress(b, loc, runtime, from, adaptor.getSource(), element, ivs);
      Value into = elementAddress(b, loc, runtime, to, adaptor.getTarget(), element, ivs);
      copyElement(b, loc, runtime, layouts, Into::Empty, at, into, element, elementType);
    });
    rewriter.eraseOp(op);
    return success();
  }
};

} // namespace

void populateMovementPatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                              const Layouts &layouts, Runtime &runtime) {
  patterns.add<LowerMoveOut<ArrayTakeOp, Out::Take>, LowerMoveOut<ArrayCopyOp, Out::Copy>,
               LowerMoveIn<ArrayPlaceOp, Into::Empty>, LowerMoveIn<ArrayPutBackOp, Into::Taken>,
               LowerArrayPlaceCopy>(converter, patterns.getContext(), layouts, runtime);
}

} // namespace idr::conversion
