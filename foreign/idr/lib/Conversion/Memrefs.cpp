// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The ops on buffers whose meaning is the runtime's: the reads and writes
// of elements of ours, and the copies that count or that no memcpy covers.
// Every other memref op of a function is upstream's: its memref-to-LLVM
// patterns lower extents, casts, views and contiguous copies of what holds
// no reference on the descriptor built at the use (Arrays.h), and the reads
// and writes of words, with the linalg ops over words, stay for upstream's
// vectorizer. An access tests nothing itself: its index is within the
// buffer, by its type or by the guard before it.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Layout.h"
#include "idr/Conversion/Arrays.h"
#include "idr/Conversion/Elements.h"
#include "idr/Conversion/IdrPattern.h"
#include "idr/Conversion/Patterns.h"
#include "idr/Conversion/Runtime.h"
#include "idr/Conversion/Words.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Dialect/MemRef/Utils/MemRefUtils.h"
#include "mlir/Transforms/DialectConversion.h"

// The runtime's C ABI: an array's header says how many object slots each
// element starts with.
#include "idris_rt.h"

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

// The address of the element a memref.load or memref.store names.
template <typename OpT>
std::pair<Value, layout::Element> elementAt(OpT op,
                                            typename IdrPattern<OpT>::OneToNOpAdaptor adaptor,
                                            ConversionPatternRewriter &rewriter,
                                            const Layouts &layouts) {
  Location loc = op.getLoc();
  MemRefType type = op.getMemRefType();
  layout::Element element = layouts.element(type.getElementType());
  Descriptor d = unpack(rewriter, loc, type, adaptor.getMemref());
  SmallVector<Value> indices;
  for (ValueRange index : adaptor.getIndices())
    indices.push_back(indexWord(rewriter, loc, index.front()));
  Value address = elementAddress(rewriter, loc, d, indices, element.stride);
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
    auto [at, element] = elementAt(op, adaptor, rewriter, layouts);
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
    auto [at, element] = elementAt(op, adaptor, rewriter, layouts);
    writeElement(rewriter, op.getLoc(), runtime, layouts, at, element,
                 op.getValueToStore().getType(), adaptor.getValue());
    rewriter.eraseOp(op);
    return success();
  }
};

// A copy whose elements hold references, or that no memcpy covers: the
// runtime's, which reads both descriptors from the frame and counts each
// element it copies and each it overwrites. A contiguous copy of elements
// whose places hold no object slot, as the array's header says, is
// upstream's memcpy.
struct LowerRuntimeCopy : IdrPattern<memref::CopyOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(memref::CopyOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    auto from = cast<MemRefType>(op.getSource().getType());
    auto to = cast<MemRefType>(op.getTarget().getType());
    layout::Element element = layouts.element(from.getElementType());
    bool slotFree = idris_rt_info_objs(element.info.word()) == 0;
    if (slotFree && contiguous(from) && contiguous(to))
      return rewriter.notifyMatchFailure(op, "a memcpy is upstream's");
    const LLVMTypeConverter &descriptors = runtime.llvmTypeConverter();
    Value fromSlot = inFrame(rewriter, loc, op,
                             descriptorOf(rewriter, loc, descriptors.convertType(from), from,
                                          adaptor.getSource()));
    Value toSlot = inFrame(
        rewriter, loc, op,
        descriptorOf(rewriter, loc, descriptors.convertType(to), to, adaptor.getTarget()));
    runtime.call(rewriter, loc, "idris_rt_memref_copy", Type(),
                 ValueRange{i64Constant(rewriter, loc, from.getRank()), fromSlot, toSlot});
    rewriter.eraseOp(op);
    return success();
  }
};

} // namespace

// The patterns of the ops on buffers whose meaning is ours, ahead of
// upstream's for the same ops.
void populateMemrefPatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                            const Layouts &layouts, Runtime &runtime) {
  MLIRContext *ctx = patterns.getContext();
  patterns.add<LowerElementLoad, LowerElementStore, LowerRuntimeCopy>(converter, ctx, layouts,
                                                                      runtime, ownLowering);
  patterns.add<LowerAsItself<TieShapeOp>>(converter, ctx, layouts, runtime);
}

} // namespace idr::conversion
