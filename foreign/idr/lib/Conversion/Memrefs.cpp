// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The ops on buffers whose meaning is the runtime's: the reads and writes
// of elements of ours, and the copies that count or that no memcpy covers;
// and the casts between ranked buffers, which change the components a
// buffer is. Every other memref op of a function is upstream's: its
// memref-to-LLVM patterns lower extents, views and contiguous copies of what holds
// no reference on the descriptor built at the use (Arrays.h), and the reads
// and writes of words, with the linalg ops over words, stay for upstream's
// vectorizer. An access tests nothing itself: its index is within the
// buffer, by its type or by the guard before it.
//
// A store and a copy write over slots that hold elements, and release what
// they overwrite: a buffer's first write, which fills slots that hold
// nothing, is a placement of its own (idr.array.place_copy, a generating
// op's place), made before any store or copy reaches the buffer.

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
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Dialect/MemRef/Utils/MemRefUtils.h"
#include "mlir/Transforms/DialectConversion.h"

using namespace mlir;

namespace idr::conversion {

namespace {

// Whether a copy between memrefs of `type` may be one memcpy: upstream's own
// rule, by which its memref.copy lowering writes llvm.intr.memcpy and
// otherwise calls a function the runtime does not have.
bool contiguous(MemRefType type) {
  return type.getLayout().isIdentity() ||
         (type.hasStaticShape() && type.getNumElements() > 0 &&
          memref::isStaticShapeAndContiguousRowMajor(type));
}

// Writes `descriptor` into a slot of the frame of the function holding
// `op`, made once per op in the entry block, and gives the slot's address:
// what idris_rt_memref_copy reads.
Value inFrame(OpBuilder &b, Location loc, Operation *op, Value descriptor) {
  Value slot;
  {
    OpBuilder::InsertionGuard guard(b);
    Operation *scope = op->getParentWithTrait<OpTrait::AutomaticAllocationScope>();
    b.setInsertionPointToStart(&scope->getRegion(0).front());
    slot = LLVM::AllocaOp::create(b, loc, ptrType(b.getContext()), descriptor.getType(),
                                  i64Constant(b, loc, 1), cellAlignment());
  }
  LLVM::StoreOp::create(b, loc, descriptor, slot, cellAlignment());
  return slot;
}

// The address of the element a memref.load or memref.store names:
// upstream's strided address over the buffer's descriptor, at the indices
// as words.
template <typename OpT>
std::pair<Value, layout::Element> elementAt(OpT op,
                                            typename IdrPattern<OpT>::OneToNOpAdaptor adaptor,
                                            ConversionPatternRewriter &rewriter,
                                            const Layouts &layouts, const Runtime &runtime) {
  Location loc = op.getLoc();
  MemRefType type = op.getMemRefType();
  layout::Element element = layouts.element(type.getElementType());
  SmallVector<Value> indices;
  for (ValueRange index : adaptor.getIndices())
    indices.push_back(indexWord(rewriter, loc, index.front()));
  const LLVMTypeConverter &descriptors = runtime.llvmTypeConverter();
  Value descriptor =
      descriptorOf(rewriter, loc, descriptors.convertType(type), type, adaptor.getMemref());
  Value address = LLVM::getStridedElementPtr(rewriter, loc, descriptors, type, descriptor,
                                             indices, LLVM::GEPNoWrapFlags::inbounds);
  return {address, std::move(element)};
}

// An element of ours read from a buffer: its slots. The reference a counted
// one needs is idr-rc's, which takes it right after the load. A word is
// upstream's.
struct LowerElementLoad : IdrPattern<memref::LoadOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(memref::LoadOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    if (holdsWords(op.getMemRefType()))
      return rewriter.notifyMatchFailure(op, "a word is upstream's");
    auto [at, element] = elementAt(op, adaptor, rewriter, layouts, runtime);
    rewriter.replaceOpWithMultiple(op, {readElement(rewriter, op.getLoc(), runtime, at, element)});
    return success();
  }
};

// An element of ours written into a buffer, over what the place held.
struct LowerElementStore : IdrPattern<memref::StoreOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(memref::StoreOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    if (holdsWords(op.getMemRefType()))
      return rewriter.notifyMatchFailure(op, "a word is upstream's");
    auto [at, element] = elementAt(op, adaptor, rewriter, layouts, runtime);
    writeElement(rewriter, op.getLoc(), runtime, layouts, at, element,
                 op.getValueToStore().getType(), adaptor.getValue());
    rewriter.eraseOp(op);
    return success();
  }
};

// A copy whose elements hold references, or that no memcpy covers: the
// runtime's, which reads both descriptors from the frame and counts each
// element it copies and each it overwrites. A contiguous copy of elements
// whose places hold no counted slot is upstream's memcpy.
struct LowerRuntimeCopy : IdrPattern<memref::CopyOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(memref::CopyOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    auto from = cast<MemRefType>(op.getSource().getType());
    auto to = cast<MemRefType>(op.getTarget().getType());
    layout::Element element = layouts.element(from.getElementType());
    bool slotFree = llvm::all_of(element.slots, [](const layout::Slot &slot) {
      return slot.word == layout::Word::Uncounted;
    });
    if (slotFree && contiguous(from) && contiguous(to))
      return rewriter.notifyMatchFailure(op, "a memcpy is upstream's");
    const LLVMTypeConverter &descriptors = runtime.llvmTypeConverter();
    Value fromSlot = inFrame(rewriter, loc, op,
                             descriptorOf(rewriter, loc, descriptors.convertType(from), from,
                                          adaptor.getSource()));
    Value toSlot = inFrame(
        rewriter, loc, op,
        descriptorOf(rewriter, loc, descriptors.convertType(to), to, adaptor.getTarget()));
    runtime.call(rewriter, loc, idr::runtime::helper::memrefCopy,
                 ValueRange{i64Constant(rewriter, loc, from.getRank()), fromSlot, toSlot});
    rewriter.eraseOp(op);
    return success();
  }
};
// A cast between ranked buffers keeps the cell and changes which fields
// of its descriptor are words of its own and which its type fixes (an
// extent made dynamic is the word its static size was). Upstream's cast
// gives back the source's value as it is, which is a descriptor's and not
// the components of a buffer of the result's type.
struct LowerCast : IdrPattern<memref::CastOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(memref::CastOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    auto from = dyn_cast<MemRefType>(op.getSource().getType());
    auto to = dyn_cast<MemRefType>(op.getType());
    if (!from || !to)
      return rewriter.notifyMatchFailure(op, "an unranked buffer is upstream's");
    Location loc = op.getLoc();
    Descriptor d = unpack(rewriter, loc, from, adaptor.getSource());
    rewriter.replaceOpWithMultiple(op, {pack(rewriter, loc, to, d)});
    return success();
  }
};

} // namespace

// The patterns of the ops on buffers whose meaning is ours, ahead of
// upstream's for the same ops.
void populateMemrefPatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                            const Layouts &layouts, Runtime &runtime) {
  MLIRContext *ctx = patterns.getContext();
  patterns.add<LowerElementLoad, LowerElementStore, LowerRuntimeCopy, LowerCast>(
      converter, ctx, layouts, runtime, ownLowering);
}

} // namespace idr::conversion
