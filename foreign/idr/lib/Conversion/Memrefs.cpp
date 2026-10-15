// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The ops on buffers: their extents, the reads and writes of elements of
// ours, their copies and their views, all on a buffer's components
// (Arrays.h). An access tests nothing itself: its index is within the
// buffer, by its type or by the guard before it. The reads and writes of
// words, and the linalg ops over words, are upstream's, which lowers and
// vectorizes them: they see the memref their buffer's components describe.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Layout.h"
#include "idr/Conversion/Arrays.h"
#include "idr/Conversion/IdrPattern.h"
#include "idr/Conversion/Patterns.h"
#include "idr/Conversion/Runtime.h"
#include "idr/Conversion/Words.h"

#include "mlir/Conversion/LLVMCommon/MemRefBuilder.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Dialect/MemRef/Utils/MemRefUtils.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/Dialect/Utils/StaticValueUtils.h"
#include "mlir/Transforms/DialectConversion.h"

// The runtime's C ABI: the size of its words.
#include "idris_rt.h"

using namespace mlir;

namespace idr::conversion {

namespace {

// The static and dynamic halves of an op's offsets, sizes or strides as
// fields: each dynamic one from the converted operands, cast to an i64.
SmallVector<OpFoldResult> mixed(OpBuilder &b, Location loc, ArrayRef<int64_t> statics,
                                ArrayRef<ValueRange> dynamics) {
  SmallVector<OpFoldResult> fields;
  size_t next = 0;
  for (int64_t value : statics)
    fields.push_back(ShapedType::isDynamic(value)
                         ? OpFoldResult(indexWord(b, loc, dynamics[next++].front()))
                         : OpFoldResult(b.getI64IntegerAttr(value)));
  return fields;
}

// Whether a copy between memrefs of `type` may be one memcpy: upstream's own
// rule for lowering memref.copy to llvm.intr.memcpy.
bool contiguous(MemRefType type) {
  return type.getLayout().isIdentity() ||
         (type.hasStaticShape() && type.getNumElements() > 0 &&
          memref::isStaticShapeAndContiguousRowMajor(type));
}

// The ranked descriptor of `type` as LLVM lays it out, its element whatever
// it is: two pointers, the offset, then the sizes and the strides.
LLVM::LLVMStructType descriptorType(MLIRContext *ctx, MemRefType type) {
  Type ptr = LLVM::LLVMPointerType::get(ctx);
  Type i64 = IntegerType::get(ctx, 64);
  SmallVector<Type> fields{ptr, ptr, i64};
  if (type.getRank() != 0) {
    auto array = LLVM::LLVMArrayType::get(i64, static_cast<unsigned>(type.getRank()));
    fields.append({array, array});
  }
  return LLVM::LLVMStructType::getLiteral(ctx, fields);
}

// Writes the descriptor `d` of `type` into a slot of the frame of the
// function holding `op`, made once per op in the entry block, and gives the
// slot's address: what idris_rt_memref_copy reads.
Value descriptorInFrame(OpBuilder &b, Location loc, Operation *op, MemRefType type,
                        const Descriptor &d) {
  auto structType = descriptorType(b.getContext(), type);
  Value slot;
  {
    OpBuilder::InsertionGuard guard(b);
    Operation *scope = op->getParentWithTrait<OpTrait::AutomaticAllocationScope>();
    b.setInsertionPointToStart(&scope->getRegion(0).front());
    slot = LLVM::AllocaOp::create(b, loc, ptrType(b.getContext()), structType,
                                  i64Constant(b, loc, 1), IDRIS_RT_WORD_BYTES);
  }
  MemRefDescriptor descriptor = MemRefDescriptor::poison(b, loc, structType);
  descriptor.setAllocatedPtr(b, loc, d.cell);
  descriptor.setAlignedPtr(b, loc, elementsOf(b, loc, d.cell));
  descriptor.setOffset(b, loc, asWord(b, loc, d.offset));
  for (auto [k, size, stride] : llvm::enumerate(d.sizes, d.strides)) {
    descriptor.setSize(b, loc, static_cast<unsigned>(k), asWord(b, loc, size));
    descriptor.setStride(b, loc, static_cast<unsigned>(k), asWord(b, loc, stride));
  }
  LLVM::StoreOp::create(b, loc, Value(descriptor), slot, IDRIS_RT_WORD_BYTES);
  return slot;
}

// An extent: the type's, or the size the descriptor holds. An index no
// constant gives selects among them; one past the rank is poison, as
// memref.dim says.
struct LowerDim : IdrPattern<memref::DimOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(memref::DimOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    auto type = cast<MemRefType>(op.getSource().getType());
    Descriptor d = unpack(rewriter, loc, type, adaptor.getSource());
    std::optional<int64_t> index = op.getConstantIndex();
    if (index) {
      Value extent = *index >= 0 && *index < type.getRank()
                         ? asIndex(rewriter, loc, d.sizes[static_cast<size_t>(*index)])
                         : Value(ub::PoisonOp::create(rewriter, loc, rewriter.getIndexType()));
      rewriter.replaceOp(op, extent);
      return success();
    }
    Value asked = adaptor.getIndex().front();
    Value extent = ub::PoisonOp::create(rewriter, loc, rewriter.getIndexType());
    for (auto [k, size] : llvm::enumerate(d.sizes)) {
      Value at = arith::ConstantIndexOp::create(rewriter, loc, static_cast<int64_t>(k));
      Value here = arith::CmpIOp::create(rewriter, loc, arith::CmpIPredicate::eq, asked, at);
      extent = arith::SelectOp::create(rewriter, loc, here, asIndex(rewriter, loc, size), extent);
    }
    rewriter.replaceOp(op, extent);
    return success();
  }
};

// The address of the element a memref.load or memref.store names.
template <typename OpT>
FailureOr<std::pair<Value, layout::Element>>
elementAt(OpT op, typename IdrPattern<OpT>::OneToNOpAdaptor adaptor,
          ConversionPatternRewriter &rewriter, const Layouts &layouts) {
  Location loc = op.getLoc();
  MemRefType type = op.getMemRefType();
  FailureOr<layout::Element> element = elementOf(op, type.getElementType(), layouts);
  if (failed(element))
    return failure();
  Descriptor d = unpack(rewriter, loc, type, adaptor.getMemref());
  SmallVector<Value> indices;
  for (ValueRange index : adaptor.getIndices())
    indices.push_back(indexWord(rewriter, loc, index.front()));
  Value address = elementAddress(rewriter, loc, d, indices, element->stride);
  return std::make_pair(address, std::move(*element));
}

// An element of ours read from a buffer: its slots. The reference a counted
// one needs is idr-rc's, which takes it right after the load.
struct LowerElementLoad : IdrPattern<memref::LoadOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(memref::LoadOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    auto at = elementAt(op, adaptor, rewriter, layouts);
    if (failed(at))
      return failure();
    rewriter.replaceOpWithMultiple(
        op, {readElement(rewriter, op.getLoc(), runtime, at->first, at->second)});
    return success();
  }
};

// An element of ours written into a buffer, over what the place held.
struct LowerElementStore : IdrPattern<memref::StoreOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(memref::StoreOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    auto at = elementAt(op, adaptor, rewriter, layouts);
    if (failed(at))
      return failure();
    writeElement(rewriter, op.getLoc(), runtime, layouts, at->first, at->second,
                 op.getValueToStore().getType(), adaptor.getValue());
    rewriter.eraseOp(op);
    return success();
  }
};

// A copy: the bytes, where no element holds a reference and both buffers are
// contiguous; otherwise the runtime's copy, which reads both descriptors and
// counts each element it copies and each it overwrites.
struct LowerCopy : IdrPattern<memref::CopyOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(memref::CopyOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    auto from = cast<MemRefType>(op.getSource().getType());
    auto to = cast<MemRefType>(op.getTarget().getType());
    FailureOr<layout::Element> element = elementOf(op, from.getElementType(), layouts);
    if (failed(element))
      return failure();
    Descriptor source = unpack(rewriter, loc, from, adaptor.getSource());
    Descriptor target = unpack(rewriter, loc, to, adaptor.getTarget());
    bool slotFree = !llvm::is_contained(layouts.counted(from.getElementType()), true);
    if (slotFree && contiguous(from) && contiguous(to)) {
      Value bytes = arith::MulIOp::create(rewriter, loc, countOf(rewriter, loc, source.sizes),
                                          i64Constant(rewriter, loc, element->stride));
      Value into = elementAddress(rewriter, loc, target, {}, element->stride);
      Value outOf = elementAddress(rewriter, loc, source, {}, element->stride);
      LLVM::MemcpyOp::create(rewriter, loc, into, outOf, bytes, /*isVolatile=*/false);
    } else {
      Value fromSlot = descriptorInFrame(rewriter, loc, op, from, source);
      Value toSlot = descriptorInFrame(rewriter, loc, op, to, target);
      runtime.call(rewriter, loc, "idris_rt_memref_copy", Type(),
                   ValueRange{i64Constant(rewriter, loc, from.getRank()), fromSlot, toSlot});
    }
    rewriter.eraseOp(op);
    return success();
  }
};

// A view the op's offset, sizes and strides describe, over its source's
// memory.
struct LowerReinterpretCast : IdrPattern<memref::ReinterpretCastOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(memref::ReinterpretCastOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    auto from = cast<MemRefType>(op.getSource().getType());
    Descriptor source = unpack(rewriter, loc, from, adaptor.getSource());
    Descriptor view{source.cell,
                    mixed(rewriter, loc, op.getStaticOffsets(), adaptor.getOffsets()).front(),
                    mixed(rewriter, loc, op.getStaticSizes(), adaptor.getSizes()),
                    mixed(rewriter, loc, op.getStaticStrides(), adaptor.getStrides())};
    rewriter.replaceOpWithMultiple(
        op, {pack(rewriter, loc, cast<MemRefType>(op.getType()), view)});
    return success();
  }
};

// A buffer's memory as a buffer of one element, then its offset, sizes and
// strides as indices.
struct LowerExtractStridedMetadata : IdrPattern<memref::ExtractStridedMetadataOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(memref::ExtractStridedMetadataOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    auto from = cast<MemRefType>(op.getSource().getType());
    Descriptor source = unpack(rewriter, loc, from, adaptor.getSource());
    SmallVector<SmallVector<Value>> results;
    Descriptor base{source.cell, rewriter.getI64IntegerAttr(0), {}, {}};
    results.push_back(
        pack(rewriter, loc, cast<MemRefType>(op.getBaseBuffer().getType()), base));
    results.push_back({asIndex(rewriter, loc, source.offset)});
    for (OpFoldResult size : source.sizes)
      results.push_back({asIndex(rewriter, loc, size)});
    for (OpFoldResult stride : source.strides)
      results.push_back({asIndex(rewriter, loc, stride)});
    rewriter.replaceOpWithMultiple(op, std::move(results));
    return success();
  }
};

// The same memory under another type: each field the result type fixes
// drops out, and each it leaves free that the source fixed is its number.
struct LowerCast : IdrPattern<memref::CastOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(memref::CastOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    auto from = cast<MemRefType>(op.getSource().getType());
    Descriptor source = unpack(rewriter, loc, from, adaptor.getSource());
    rewriter.replaceOpWithMultiple(op,
                                   {pack(rewriter, loc, cast<MemRefType>(op.getType()), source)});
    return success();
  }
};

// The source's memory with its dimensions in the permutation's order.
struct LowerTranspose : IdrPattern<memref::TransposeOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(memref::TransposeOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    auto from = cast<MemRefType>(op.getIn().getType());
    Descriptor source = unpack(rewriter, loc, from, adaptor.getIn());
    Descriptor view{source.cell, source.offset, {}, {}};
    for (AffineExpr result : op.getPermutation().getResults()) {
      unsigned at = cast<AffineDimExpr>(result).getPosition();
      view.sizes.push_back(source.sizes[at]);
      view.strides.push_back(source.strides[at]);
    }
    rewriter.replaceOpWithMultiple(op,
                                   {pack(rewriter, loc, cast<MemRefType>(op.getType()), view)});
    return success();
  }
};

} // namespace

Value toMemref(OpBuilder &b, Location loc, const Runtime &runtime, MemRefType type,
               ValueRange components) {
  if (!holdsWords(type))
    return nullptr;
  Type converted = runtime.llvmTypeConverter().convertType(type);
  if (!converted)
    return nullptr;
  Descriptor d = unpack(b, loc, type, components);
  MemRefDescriptor descriptor = MemRefDescriptor::poison(b, loc, converted);
  descriptor.setAllocatedPtr(b, loc, d.cell);
  descriptor.setAlignedPtr(b, loc, elementsOf(b, loc, d.cell));
  descriptor.setOffset(b, loc, asWord(b, loc, d.offset));
  for (auto [k, size, stride] : llvm::enumerate(d.sizes, d.strides)) {
    descriptor.setSize(b, loc, static_cast<unsigned>(k), asWord(b, loc, size));
    descriptor.setStride(b, loc, static_cast<unsigned>(k), asWord(b, loc, stride));
  }
  return UnrealizedConversionCastOp::create(b, loc, type, Value(descriptor)).getResult(0);
}

// The patterns of the ops on buffers.
void populateMemrefPatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                            const Layouts &layouts, Runtime &runtime) {
  patterns.add<LowerDim, LowerElementLoad, LowerElementStore, LowerCopy, LowerReinterpretCast,
               LowerExtractStridedMetadata, LowerCast, LowerTranspose, LowerAsItself<TieShapeOp>>(
      converter, patterns.getContext(), layouts, runtime);
}

} // namespace idr::conversion
