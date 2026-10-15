// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A machine word in a buffer of bytes. The buffer is a memref of bytes a
// world orders: its cell and its size (Arrays.h). The word is at its offset
// from the first byte, right after the cell's header, where the op's guard
// found its bytes within that size: the access tests nothing itself. The
// load and the store are the target's own, at alignment 1: the endianness
// is the machine's, and the offset need not be aligned.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Layout.h"
#include "idr/Conversion/Arrays.h"
#include "idr/Conversion/IdrPattern.h"
#include "idr/Conversion/Patterns.h"
#include "idr/Conversion/Runtime.h"
#include "idr/Conversion/Words.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Transforms/DialectConversion.h"

using namespace mlir;

namespace idr::conversion {

namespace {

// The address of the byte at `offset` in the buffer `buffer`, whose
// components are `components`.
Value byteAt(OpBuilder &b, Location loc, Value buffer, ValueRange components, Value offset) {
  auto type = cast<MemRefType>(unrestricted(buffer.getType()));
  return elementAddress(b, loc, unpack(b, loc, type, components), offset, 1);
}

struct LowerBufferLoad : IdrPattern<BufferLoadOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(BufferLoadOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    Type word = this->layouts.components(op.getValue().getType()).front();
    Value addr = byteAt(rewriter, loc, op.getBuffer(), adaptor.getBuffer(),
                        adaptor.getOffset().front());
    Value loaded = LLVM::LoadOp::create(rewriter, loc, word, addr, /*alignment=*/1);
    rewriter.replaceOpWithMultiple(op, {SmallVector<Value>{loaded}, SmallVector<Value>{}});
    return success();
  }
};

struct LowerBufferStore : IdrPattern<BufferStoreOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(BufferStoreOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    Value addr = byteAt(rewriter, loc, op.getBuffer(), adaptor.getBuffer(),
                        adaptor.getOffset().front());
    LLVM::StoreOp::create(rewriter, loc, adaptor.getValue().front(), addr, /*alignment=*/1);
    rewriter.replaceOpWithMultiple(op, {SmallVector<Value>{}});
    return success();
  }
};

} // namespace

void populateBufferPatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                            const Layouts &layouts, Runtime &runtime) {
  patterns.add<LowerBufferLoad, LowerBufferStore>(converter, patterns.getContext(), layouts,
                                                  runtime);
}

} // namespace idr::conversion
