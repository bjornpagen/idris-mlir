// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The cells memrefs live in, which the runtime allocates or which are
// constants; mutable memory's reads, writes and updates in place; and the
// three movements a step of a generating op makes in its buffers (take,
// copy, place). A memref's runtime form is Descriptors.cpp's, an element's
// place Elements.cpp's, and the other ops on buffers Memrefs.cpp's. An
// access tests nothing itself: its index is within the array, by its type
// or by the guard before it.
//
// A read borrows its element: the reference a reader keeps is counting's
// to take, placed before the lowering. A write releases what it replaces
// and a new array's fill is taken once per element, the runtime meaning of
// mutable memory. A step's place puts a value where its slots hold nothing,
// so it releases nothing; a cell of a step is moved slot by slot. A copy
// placed in a buffer allocated for it releases nothing either.
//
// No cell is filled before its first write: each maker writes every element
// whole before anything reads, releases or frees the cell (a new array its
// fill, a step its moves, and a buffer bufferization allocates its first
// writer, a placed copy or the generating op whose destination it is).

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Layout.h"
#include "idr/Conversion/Arrays.h"
#include "idr/Conversion/Elements.h"
#include "idr/Conversion/IdrPattern.h"
#include "idr/Conversion/Patterns.h"
#include "idr/Conversion/Runtime.h"
#include "idr/Conversion/Words.h"

#include "mlir/Conversion/LLVMCommon/Pattern.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/Utils/StaticValueUtils.h"
#include "mlir/Transforms/DialectConversion.h"
#include "llvm/Support/MathExtras.h"

#include <type_traits>

using namespace mlir;

namespace idr::conversion {

namespace {

// A new cell of `count` elements of `element`, from the runtime: fresh
// memory, which no other pointer reaches, its elements unwritten, which its
// maker writes before anything reads, releases or frees them. Fresh is said
// at the call (the runtime's definition replaces the declaration's
// attributes when it is linked in), so that a loop over two arrays keeps
// what it accumulates in a register across the reads of the other.
Value newCell(OpBuilder &b, Location loc, Runtime &runtime, Value count,
              const layout::Element &element) {
  LLVM::CallOp cell = runtime.call(b, loc, idr::runtime::helper::arrayNewUnwritten,
                                   ValueRange{count, i32Constant(b, loc, element.info.word())});
  cell.setResAttrsAttr(b.getArrayAttr(b.getDictionaryAttr(
      b.getNamedAttr(LLVM::LLVMDialect::getNoAliasAttrName(), b.getUnitAttr()))));
  return cell.getResult();
}

// A buffer's cell: as many elements as the product of the extents, a
// product past 64 bits being UINT64_MAX, which the runtime finds too large
// for any cell. The buffer is the cell and each dynamic size. That the
// allocation is a cell's, in the identity layout and aligned no further
// than a word, is the program's verifier's rule; that its first writer
// writes it whole, before anything reads or releases a slot, is
// idr-bufferize's, which made it.
struct LowerAlloc : IdrPattern<memref::AllocOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(memref::AllocOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    MemRefType type = op.getType();
    layout::Element element = layouts.element(type.getElementType());
    // The product saturates at each step, so a later empty extent still
    // makes it 0.
    uint64_t known = 1;
    for (int64_t extent : type.getShape())
      if (!ShapedType::isDynamic(extent))
        known = llvm::SaturatingMultiply(known, static_cast<uint64_t>(extent));
    Value most = i64Constant(rewriter, loc, -1);
    Value count = i64Constant(rewriter, loc, static_cast<int64_t>(known));
    auto pair = LLVM::LLVMStructType::getLiteral(getContext(),
                                                 {rewriter.getI64Type(), rewriter.getI1Type()});
    SmallVector<Value> extents;
    for (ValueRange size : adaptor.getDynamicSizes()) {
      Value extent = indexWord(rewriter, loc, size.front());
      extents.push_back(extent);
      Value product = LLVM::UMulWithOverflowOp::create(rewriter, loc, pair, count, extent);
      count = arith::SelectOp::create(rewriter, loc,
                                      LLVM::ExtractValueOp::create(rewriter, loc, product, 1), most,
                                      LLVM::ExtractValueOp::create(rewriter, loc, product, 0));
    }
    SmallVector<Value> components{newCell(rewriter, loc, runtime, count, element)};
    llvm::append_range(components, extents);
    rewriter.replaceOpWithMultiple(op, {components});
    return success();
  }
};

// A constant array: its static cell, the header in front of the data. Its
// value is any constant elements bufferization gave the global: dense, a
// resource, or another form, each written as the cell's data. Every global
// of the program was read as a constant array before any function is
// lowered, and a verified get_global names one of them.
struct LowerGetGlobal : IdrPattern<memref::GetGlobalOp> {
  LowerGetGlobal(const TypeConverter &converter, MLIRContext *ctx, const Layouts &layouts,
                 Runtime &runtime, const DenseMap<StringAttr, ConstantArray> &arrays)
      : IdrPattern(converter, ctx, layouts, runtime), arrays(arrays) {}

  LogicalResult matchAndRewrite(memref::GetGlobalOp op, OneToNOpAdaptor,
                                ConversionPatternRewriter &rewriter) const override {
    const ConstantArray &array = arrays.at(op.getNameAttr().getAttr());
    rewriter.replaceOpWithMultiple(
        op, {SmallVector<Value>{runtime.constantArray(rewriter, op.getLoc(), array)}});
    return success();
  }

  const DenseMap<StringAttr, ConstantArray> &arrays;
};

// A new array of mutable memory, of the given sizes (an array of rank 0 has
// one element), each element the fill: its components placed in each
// element, each counted one taking a reference per element, and the fill's
// own given up after. A static fill takes none: its count is the runtime's
// persistent mark. The elements are in a row from the cell's first, each
// its stride's bytes after the one before (Layouts::element).
struct LowerArrayNew : IdrPattern<ArrayNewOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(ArrayNewOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    auto type = cast<MemRefType>(unrestricted(op.getArray().getType()));
    layout::Element element = layouts.element(type.getElementType());
    SmallVector<Value> sizes;
    for (ValueRange size : adaptor.getSizes())
      sizes.push_back(indexWord(rewriter, loc, size.front()));
    Value count = countOf(rewriter, loc, getAsOpFoldResult(sizes));
    Value cell = newCell(rewriter, loc, runtime, count, element);
    ValueRange fill = adaptor.getFill();
    SmallVector<layout::Component> held = layouts.components(op.getFill().getType());
    Value first = elementsOf(rewriter, loc, cell);
    Type bytes = LLVM::LLVMArrayType::get(rewriter.getI8Type(), element.stride);
    Value lower = arith::ConstantIndexOp::create(rewriter, loc, 0);
    Value upper = arith::IndexCastOp::create(rewriter, loc, rewriter.getIndexType(), count);
    Value step = arith::ConstantIndexOp::create(rewriter, loc, 1);
    auto loop = scf::ForOp::create(rewriter, loc, lower, upper, step);
    {
      OpBuilder::InsertionGuard guard(rewriter);
      rewriter.setInsertionPointToStart(loop.getBody());
      Value at = LLVM::GEPOp::create(
          rewriter, loc, ptrType(getContext()), bytes, first,
          ArrayRef<LLVM::GEPArg>{indexWord(rewriter, loc, loop.getInductionVar())},
          LLVM::GEPNoWrapFlags::inbounds);
      placeElement(rewriter, loc, runtime, at, element, fill);
      runtime.inc(rewriter, loc, held, fill);
    }
    runtime.dec(rewriter, loc, held, fill);
    SmallVector<Value> array{cell};
    llvm::append_range(array, sizes);
    rewriter.replaceOpWithMultiple(op, {array});
    return success();
  }
};

// The memref type upstream's getStridedElementPtr addresses an element of
// `type` through, `element` its layout: `type` itself, whose element the
// descriptors converter gives as what an element holds (a word as itself,
// an element of ours as its bytes), so the address steps by the element's
// stride. An element that is itself an array is what the converter cannot
// give: it gives an array as the descriptor a value of it is in a
// function, while an element holds its components (Layouts::element), two
// runtime forms of one type that no conversion of the type alone tells
// apart. Only mutable memory holds an array (a value array holds no shaped
// element), and its layout is the identity of rank 1 at most, whose strides
// its type fixes: it is addressed as a view of the same cell's bytes, each
// stride scaled by the element's.
MemRefType addressedAs(MemRefType type, const layout::Element &element) {
  if (!isa<ShapedType>(type.getElementType()))
    return type;
  auto [strides, offset] = type.getStridesAndOffset();
  auto scaled = [&](int64_t elements) { return elements * static_cast<int64_t>(element.stride); };
  MLIRContext *ctx = type.getContext();
  return MemRefType::get(
      type.getShape(), IntegerType::get(ctx, 8),
      StridedLayoutAttr::get(ctx, scaled(offset), llvm::map_to_vector(strides, scaled)),
      type.getMemorySpace());
}

// The address of the element at `indices`, each an index converted to a
// word, of a buffer of `type` whose components are `components`: upstream's
// strided address over its descriptor.
Value elementAddress(OpBuilder &b, Location loc, const Runtime &runtime, MemRefType type,
                     ValueRange components, const layout::Element &element,
                     ValueRange indices) {
  SmallVector<Value> words =
      llvm::map_to_vector(indices, [&](Value index) { return indexWord(b, loc, index); });
  const LLVMTypeConverter &descriptors = runtime.llvmTypeConverter();
  Value descriptor = descriptorOf(b, loc, descriptors.convertType(type), type, components);
  return LLVM::getStridedElementPtr(b, loc, descriptors, addressedAs(type, element), descriptor,
                                    words, LLVM::GEPNoWrapFlags::inbounds);
}

// Each index of a converted operand group, one value each.
SmallVector<Value> indicesOf(ArrayRef<ValueRange> indices) {
  return llvm::map_to_vector(indices, [](ValueRange index) { return index.front(); });
}

// An element of mutable memory, borrowed: the array keeps its reference.
struct LowerArrayGet : IdrPattern<ArrayGetOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(ArrayGetOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    auto type = cast<MemRefType>(unrestricted(op.getArray().getType()));
    layout::Element element = layouts.element(type.getElementType());
    Value at = elementAddress(rewriter, op.getLoc(), runtime, type, adaptor.getArray(), element,
                              indicesOf(adaptor.getIndices()));
    rewriter.replaceOpWithMultiple(op, {readElement(rewriter, op.getLoc(), runtime, at, element)});
    return success();
  }
};

// A write releases the old element and moves the new one in.
struct LowerArraySet : IdrPattern<ArraySetOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(ArraySetOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    auto type = cast<MemRefType>(unrestricted(op.getArray().getType()));
    layout::Element element = layouts.element(type.getElementType());
    Value at = elementAddress(rewriter, op.getLoc(), runtime, type, adaptor.getArray(), element,
                              indicesOf(adaptor.getIndices()));
    writeElement(rewriter, op.getLoc(), runtime, layouts, at, element, op.getValue().getType(),
                 adaptor.getValue());
    rewriter.eraseOp(op);
    return success();
  }
};

// An element rebuilt in its place, in mutable memory or in a value array's
// buffer. It moves out into the region with the reference the array held,
// the region runs once, here, as an scf.execute_region whose yield is the
// region's, and the first value it gives moves back into the place it left
// (a boxed element into the box it left where the place alone held it);
// the values after it are the op's results. A region that never returns
// ends as it is.
struct LowerUpdate : IdrPattern<ArrayUpdateOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(ArrayUpdateOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    auto type = cast<MemRefType>(unrestricted(op.getArray().getType()));
    Type elementType = type.getElementType();
    // What the region gives, as the converter gives it, the one source of
    // the region's converted signature: the element, then each result.
    // Asked before any op is made, so a type the converter does not take
    // leaves the op as it is.
    SmallVector<Type> types{elementType};
    llvm::append_range(types, op.getOuts().getTypes());
    SmallVector<SmallVector<Type>> given(types.size());
    for (auto [one, converted] : llvm::zip_equal(types, given))
      if (failed(getTypeConverter()->convertType(one, converted)))
        return rewriter.notifyMatchFailure(op, "a value the region gives has no lowered type");
    layout::Element element = layouts.element(elementType);
    Value at = elementAddress(rewriter, loc, runtime, type, adaptor.getArray(), element,
                              indicesOf(adaptor.getIndices()));
    Taken taken = takeElement(rewriter, loc, runtime, layouts, at, element, elementType);
    SmallVector<Type> flat;
    for (ArrayRef<Type> components : given)
      llvm::append_range(flat, components);
    Block *body = &op.getRegion().front();
    TypeConverter::SignatureConversion entry(body->getNumArguments());
    entry.remapInput(0, taken.value);
    rewriter.applySignatureConversion(body, entry, getTypeConverter());
    auto run = scf::ExecuteRegionOp::create(rewriter, loc, flat);
    rewriter.inlineRegionBefore(op.getRegion(), run.getRegion(), run.getRegion().end());
    ValueRange values = run.getResults();
    putBack(rewriter, loc, runtime, at, element, taken, values.take_front(given.front().size()));
    values = values.drop_front(given.front().size());
    SmallVector<SmallVector<Value>> results;
    for (ArrayRef<Type> out : ArrayRef(given).drop_front()) {
      results.push_back(SmallVector<Value>(values.take_front(out.size())));
      values = values.drop_front(out.size());
    }
    rewriter.replaceOpWithMultiple(op, std::move(results));
    return success();
  }
};

// The end of an update's region: its values, component by component, are
// the region's results.
struct LowerUpdateYield : IdrPattern<ArrayUpdateYieldOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(ArrayUpdateYieldOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    SmallVector<Value> flat(adaptor.getElement());
    for (ValueRange value : adaptor.getOuts())
      llvm::append_range(flat, value);
    rewriter.replaceOpWithNewOp<scf::YieldOp>(op, flat);
    return success();
  }
};

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

// The patterns of the cells memrefs live in, constant or allocated, of
// mutable memory, of the elements of a buffer rebuilt in place, of a
// step's movements, and of a fresh buffer's placed copy.
void populateArrayPatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                           const Layouts &layouts, Runtime &runtime,
                           const DenseMap<StringAttr, ConstantArray> &arrays) {
  MLIRContext *ctx = patterns.getContext();
  patterns.add<LowerAlloc, LowerArrayNew, LowerArrayGet, LowerArraySet, LowerUpdate,
               LowerUpdateYield, LowerMoveOut<ArrayTakeOp, Movement::Take>,
               LowerMoveOut<ArrayCopyOp, Movement::Copy>, LowerArrayPlace, LowerArrayPlaceCopy>(
      converter, ctx, layouts, runtime);
  patterns.add<LowerGetGlobal>(converter, ctx, layouts, runtime, arrays);
}

} // namespace idr::conversion
