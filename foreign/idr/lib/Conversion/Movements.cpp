// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The three movements a step of a generating op makes in its buffers (take,
// copy, place), and the copy placed in a buffer allocated for it. Each
// moves what the slots under its indices hold: an element, at its place
// (Elements.h), or a cell's elements one by one, in row-major order.
//
// A take moves out what the slots hold, which then hold nothing to
// release; a copy reads it with references of its own, the slots keeping
// theirs; a place puts a value where the slots hold nothing, so it
// releases nothing. A copy placed in a buffer allocated for it releases
// nothing either: its target's slots were never written.

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

#include <type_traits>

using namespace mlir;

namespace idr::conversion {

namespace {

// What a step moves, and how: out of slots that then hold nothing (take),
// out with references of its own, the slots keeping theirs (copy), or into
// slots that hold nothing (place). A cell is moved element by element, its
// slots under the step's leading indices.
enum class Movement { Take, Copy, Place };

// The element at `from` moved to `to`, as `movement` moves it; `type` the
// element's.
void moveElement(OpBuilder &b, Location loc, Runtime &runtime, const Layouts &layouts,
                 Movement movement, Value from, Value to, const layout::Element &element,
                 Type type) {
  SmallVector<Value> value = readElement(b, loc, runtime, from, element);
  placeElement(b, loc, runtime, to, element, value);
  if (movement != Movement::Take)
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
// or a fresh cell of the elements under them.
template <typename OpT, Movement movement>
struct LowerMoveOut : IdrPattern<OpT> {
  using IdrPattern<OpT>::IdrPattern;
  LogicalResult matchAndRewrite(OpT op, typename IdrPattern<OpT>::OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    auto type = cast<MemRefType>(op.getBuffer().getType());
    Type elementType = type.getElementType();
    layout::Element element = this->layouts.element(elementType);
    SmallVector<Value> indices = indicesOf(adaptor.getIndices());
    auto cellType = dyn_cast<MemRefType>(op.getValue().getType());
    if (!cellType) {
      Value from = elementAddress(rewriter, loc, this->runtime, type, adaptor.getBuffer(), element,
                                  indices);
      SmallVector<Value> value = readElement(rewriter, loc, this->runtime, from, element);
      if constexpr (movement == Movement::Copy)
        this->runtime.inc(rewriter, loc, this->layouts.components(elementType), value);
      rewriter.replaceOpWithMultiple(op, {value});
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
      moveElement(b, loc, this->runtime, this->layouts, movement, from, to, element, elementType);
    });
    rewriter.replaceOpWithMultiple(op, {made});
    return success();
  }
};

// A place: the value into the slots under the op's indices, which hold
// nothing. A cell's elements are copied in, each with a reference of its
// own, and the cell's own reference is given up: whether another value
// shares the cell is known only at run time, from its count, and a cell no
// one else holds is freed, its elements losing the references the copy
// gave them back.
struct LowerArrayPlace : IdrPattern<ArrayPlaceOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(ArrayPlaceOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    auto type = cast<MemRefType>(op.getBuffer().getType());
    Type elementType = type.getElementType();
    layout::Element element = layouts.element(elementType);
    SmallVector<Value> indices = indicesOf(adaptor.getIndices());
    auto cellType = dyn_cast<MemRefType>(op.getValue().getType());
    if (!cellType) {
      Value to = elementAddress(rewriter, loc, runtime, type, adaptor.getBuffer(), element, indices);
      placeElement(rewriter, loc, runtime, to, element, adaptor.getValue());
      rewriter.eraseOp(op);
      return success();
    }
    ValueRange value = adaptor.getValue();
    CellOf cell = cellOf(rewriter, loc, cellType, value, 0);
    forEachElement(rewriter, loc, cell.sizes, [&](OpBuilder &b, ValueRange ivs) {
      SmallVector<Value> at(indices);
      llvm::append_range(at, ivs);
      Value from = elementAddress(b, loc, runtime, cellType, value, element, ivs);
      Value to = elementAddress(b, loc, runtime, type, adaptor.getBuffer(), element, at);
      moveElement(b, loc, runtime, layouts, Movement::Copy, from, to, element, elementType);
    });
    runtime.dec(rewriter, loc, layout::Word::Cell, value.front());
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
      moveElement(b, loc, runtime, layouts, Movement::Copy, at, into, element, elementType);
    });
    rewriter.eraseOp(op);
    return success();
  }
};

} // namespace

void populateMovementPatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                              const Layouts &layouts, Runtime &runtime) {
  patterns.add<LowerMoveOut<ArrayTakeOp, Movement::Take>, LowerMoveOut<ArrayCopyOp, Movement::Copy>,
               LowerArrayPlace, LowerArrayPlaceCopy>(converter, patterns.getContext(), layouts,
                                                     runtime);
}

} // namespace idr::conversion
