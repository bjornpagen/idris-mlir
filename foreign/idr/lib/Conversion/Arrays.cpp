// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The cells memrefs live in, which the runtime allocates or which are
// constants, and the arrays a world orders: their reads, writes and updates
// in place. A memref's runtime form is Descriptors.cpp's, an element's place
// Elements.cpp's, and the other ops on buffers Memrefs.cpp's. An access
// tests nothing itself: its index is within the array, by its type or by
// the guard before it.

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

using namespace mlir;

namespace idr::conversion {

namespace {

// A new cell of `count` elements of `element`, from the runtime: fresh
// memory, which no other pointer reaches. Said at the call (the runtime's
// definition replaces the declaration's attributes when it is linked in),
// so that a loop over two arrays keeps what it accumulates in a register
// across the reads of the other.
Value newCell(OpBuilder &b, Location loc, Runtime &runtime, Value count,
              const layout::Element &element) {
  LLVM::CallOp cell = runtime.call(b, loc, idr::runtime::helper::arrayNew,
                                   ValueRange{count, i32Constant(b, loc, element.info.word())});
  cell.setResAttrsAttr(b.getArrayAttr(b.getDictionaryAttr(
      b.getNamedAttr(LLVM::LLVMDialect::getNoAliasAttrName(), b.getUnitAttr()))));
  return cell.getResult();
}

// A buffer's cell: as many elements as the product of the extents, a
// product past 64 bits being UINT64_MAX, which the runtime finds too large
// for any cell. The buffer is the cell and each dynamic size. That the
// allocation is a cell's, in the identity layout and aligned no further
// than a word, is the program's verifier's rule.
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

// A new array a world orders, of the given sizes (a negative size is an
// empty dimension; an array of rank 0 has one element), each element the
// fill: its components placed in each element, each counted one taking a
// reference per element, and the fill's own given up after. A static fill
// takes none: its count is the runtime's persistent mark. The elements are
// in a row from the cell's first, each its stride's bytes after the one
// before (Layouts::element).
struct LowerArrayNew : IdrPattern<ArrayNewOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(ArrayNewOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    layout::Element element = layouts.element(op.getArrayType().getElementType());
    Value zero = arith::ConstantIntOp::create(rewriter, loc, 0, 64);
    SmallVector<Value> sizes;
    for (ValueRange size : adaptor.getSizes())
      sizes.push_back(arith::MaxSIOp::create(rewriter, loc, size.front(), zero));
    Value count = countOf(rewriter, loc, getAsOpFoldResult(sizes));
    Value cell = newCell(rewriter, loc, runtime, count, element);
    ValueRange fill = adaptor.getFill();
    SmallVector<Value> held = references(layouts.components(op.getFill().getType()), fill);
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
      runtime.inc(rewriter, loc, held);
    }
    runtime.dec(rewriter, loc, held);
    SmallVector<Value> array{cell};
    llvm::append_range(array, sizes);
    rewriter.replaceOpWithMultiple(op, {array, SmallVector<Value>{}});
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
// apart. Only an array a world orders holds an array (a value array holds
// no shaped element), and its layout is the identity of rank 1 at most,
// whose strides its type fixes: it is addressed as a view of the same
// cell's bytes, each stride scaled by the element's.
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

// The address of the element an access or an update names, at its i64
// indices, in an array a world orders or in a value array's buffer:
// upstream's strided address over the array's descriptor.
template <typename OpT>
Value addressOf(OpT op, typename IdrPattern<OpT>::OneToNOpAdaptor adaptor,
                const layout::Element &element, const Runtime &runtime,
                ConversionPatternRewriter &rewriter) {
  Location loc = op.getLoc();
  MemRefType type = op.getArrayType();
  SmallVector<Value> indices;
  for (ValueRange index : adaptor.getIndices())
    indices.push_back(index.front());
  const LLVMTypeConverter &descriptors = runtime.llvmTypeConverter();
  Value descriptor =
      descriptorOf(rewriter, loc, descriptors.convertType(type), type, adaptor.getArray());
  return LLVM::getStridedElementPtr(rewriter, loc, descriptors, addressedAs(type, element),
                                    descriptor, indices, LLVM::GEPNoWrapFlags::inbounds);
}

// An element of an array a world orders, which keeps its own reference:
// the read takes one of its own.
struct LowerArrayGet : IdrPattern<ArrayGetOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(ArrayGetOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    layout::Element element = layouts.element(op.getArrayType().getElementType());
    Value at = addressOf(op, adaptor, element, runtime, rewriter);
    SmallVector<Value> value = readElement(rewriter, loc, runtime, at, element);
    runtime.inc(rewriter, loc, references(layouts.components(op.getValue().getType()), value));
    rewriter.replaceOpWithMultiple(op, {value, SmallVector<Value>{}});
    return success();
  }
};

// A write releases the old element and moves the new one in.
struct LowerArraySet : IdrPattern<ArraySetOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(ArraySetOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    layout::Element element = layouts.element(op.getArrayType().getElementType());
    Value at = addressOf(op, adaptor, element, runtime, rewriter);
    writeElement(rewriter, op.getLoc(), runtime, layouts, at, element, op.getValue().getType(),
                 adaptor.getValue());
    rewriter.replaceOpWithMultiple(op, {SmallVector<Value>{}});
    return success();
  }
};

// An element rebuilt in its place, in an array a world orders or in a value
// array's buffer. It moves out into the region with the reference the array
// held, the region runs once, here, as an scf.execute_region whose yield is
// the region's, and the first value it yields moves back in over the place
// it left, which holds nothing to release; the values after it are the op's
// results, and a world after them is nothing. A region that never returns
// ends as it is, in ub.unreachable.
template <typename OpT>
struct LowerUpdate : IdrPattern<OpT> {
  using IdrPattern<OpT>::IdrPattern;
  LogicalResult matchAndRewrite(OpT op, typename IdrPattern<OpT>::OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    Type elementType = op.getArrayType().getElementType();
    // What the region yields, as the converter gives it, the one source of
    // the region's converted signature: the element, then each result. Asked
    // before any op is made, so a type the converter does not take leaves
    // the op as it is.
    SmallVector<Type> types{elementType};
    llvm::append_range(types, op.getOuts().getTypes());
    SmallVector<SmallVector<Type>> yielded(types.size());
    for (auto [type, converted] : llvm::zip_equal(types, yielded))
      if (failed(this->getTypeConverter()->convertType(type, converted)))
        return rewriter.notifyMatchFailure(op, "a value the region yields has no lowered type");
    layout::Element element = this->layouts.element(elementType);
    Value at = addressOf(op, adaptor, element, this->runtime, rewriter);
    SmallVector<Value> old =
        takeElement(rewriter, loc, this->runtime, this->layouts, at, element, elementType);
    SmallVector<Type> flat;
    for (ArrayRef<Type> components : yielded)
      llvm::append_range(flat, components);
    TypeConverter::SignatureConversion entry(op.getBody()->getNumArguments());
    entry.remapInput(0, old);
    rewriter.applySignatureConversion(op.getBody(), entry, this->getTypeConverter());
    auto run = scf::ExecuteRegionOp::create(rewriter, loc, flat);
    rewriter.inlineRegionBefore(op.getRegion(), run.getRegion(), run.getRegion().end());
    ValueRange values = run.getResults();
    placeElement(rewriter, loc, this->runtime, at, element,
                 values.take_front(yielded.front().size()));
    values = values.drop_front(yielded.front().size());
    SmallVector<SmallVector<Value>> results;
    for (ArrayRef<Type> out : ArrayRef(yielded).drop_front()) {
      results.push_back(SmallVector<Value>(values.take_front(out.size())));
      values = values.drop_front(out.size());
    }
    results.resize(op->getNumResults());
    rewriter.replaceOpWithMultiple(op, std::move(results));
    return success();
  }
};

// The end of an update's region: its values, component by component, are
// the region's results. No other op of the generating set reaches the
// lowering: idr-structure-loops has made each loops.
struct LowerArrayYield : IdrPattern<ArrayYieldOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(ArrayYieldOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    SmallVector<Value> flat;
    for (ValueRange value : adaptor.getValues())
      llvm::append_range(flat, value);
    rewriter.replaceOpWithNewOp<scf::YieldOp>(op, flat);
    return success();
  }
};

} // namespace

// The patterns of the cells memrefs live in, constant or allocated, of the
// arrays a world orders, and of the elements of a value array's buffer
// rebuilt in place.
void populateArrayPatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                           const Layouts &layouts, Runtime &runtime,
                           const DenseMap<StringAttr, ConstantArray> &arrays) {
  MLIRContext *ctx = patterns.getContext();
  patterns.add<LowerAlloc, LowerArrayNew, LowerArrayGet, LowerArraySet,
               LowerUpdate<ArrayUpdateOp>, LowerUpdate<ElementUpdateOp>, LowerArrayYield>(
      converter, ctx, layouts, runtime);
  patterns.add<LowerGetGlobal>(converter, ctx, layouts, runtime, arrays);
}

} // namespace idr::conversion
