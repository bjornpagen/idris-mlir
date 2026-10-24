// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The cells memrefs live in, which the runtime allocates or which are
// constants; and mutable memory's reads, writes and updates in place, with
// a value array's buffer's updates. A memref's runtime form is
// Descriptors.cpp's, an element's place and address Elements.cpp's, a
// step's movements Movements.cpp's, and the other ops on buffers
// Memrefs.cpp's. An access tests nothing itself: its index is within the
// array, by its type or by the guard before it.
//
// A read borrows its element: the reference a reader keeps is counting's
// to take, placed before the lowering. A write releases what it replaces
// and a new array's fill is taken once per element, the runtime meaning of
// mutable memory.
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

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/Utils/StaticValueUtils.h"
#include "mlir/Transforms/DialectConversion.h"
#include "llvm/Support/MathExtras.h"

using namespace mlir;

namespace idr::conversion {

// Fresh is said at the call (the runtime's definition replaces the
// declaration's attributes when it is linked in), so that a loop over two
// arrays keeps what it accumulates in a register across the reads of the
// other.
Value newCell(OpBuilder &b, Location loc, Runtime &runtime, Value count,
              const layout::Element &element) {
  LLVM::CallOp cell = runtime.call(b, loc, idr::runtime::helper::arrayNewUnwritten,
                                   ValueRange{count, i32Constant(b, loc, element.info.word())});
  cell.setResAttrsAttr(b.getArrayAttr(b.getDictionaryAttr(
      b.getNamedAttr(LLVM::LLVMDialect::getNoAliasAttrName(), b.getUnitAttr()))));
  return cell.getResult();
}

namespace {

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
// of the program was made a static cell before any function is lowered, and
// a verified get_global names one of them.
struct LowerGetGlobal : IdrPattern<memref::GetGlobalOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(memref::GetGlobalOp op, OneToNOpAdaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Value cell =
        staticAddress(rewriter, op.getLoc(), runtime.statics().array(op.getNameAttr().getAttr()));
    rewriter.replaceOpWithMultiple(op, {SmallVector<Value>{cell}});
    return success();
  }
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
// region's, and the first value it gives is put back into the place it left
// (takeOut, putIn: the take and the put-back of a split update's); the
// values after it are the op's results. A region that never returns ends
// as it is.
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
    SmallVector<Value> taken = takeOut(rewriter, loc, runtime, layouts, at, element, elementType,
                                       boxSharingOf(op.getArray().getType()));
    SmallVector<Type> flat;
    for (ArrayRef<Type> components : given)
      llvm::append_range(flat, components);
    Block *body = &op.getRegion().front();
    TypeConverter::SignatureConversion entry(body->getNumArguments());
    entry.remapInput(0, taken);
    rewriter.applySignatureConversion(body, entry, getTypeConverter());
    auto run = scf::ExecuteRegionOp::create(rewriter, loc, flat);
    rewriter.inlineRegionBefore(op.getRegion(), run.getRegion(), run.getRegion().end());
    ValueRange values = run.getResults();
    putIn(rewriter, loc, runtime, at, element, values.take_front(given.front().size()));
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

} // namespace

// The patterns of the cells memrefs live in, constant or allocated, of
// mutable memory, of the elements of a buffer rebuilt in place, and of a
// step's movements and a fresh buffer's placed copy (Movements.cpp).
void populateArrayPatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                           const Layouts &layouts, Runtime &runtime) {
  MLIRContext *ctx = patterns.getContext();
  patterns.add<LowerAlloc, LowerArrayNew, LowerArrayGet, LowerArraySet, LowerUpdate,
               LowerUpdateYield, LowerGetGlobal>(converter, ctx, layouts, runtime);
  populateMovementPatterns(patterns, converter, layouts, runtime);
}

} // namespace idr::conversion
