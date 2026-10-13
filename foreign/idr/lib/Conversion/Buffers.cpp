// A machine word in a buffer of bytes. The buffer is the array cell and its
// length. The word is at its offset from the first byte, where the op's guard
// found its bytes within that length, or a proof did where it removed the
// guard: the access tests nothing itself. The load and the store are the
// target's own, at alignment 1: the endianness is the machine's, and the
// offset need not be aligned.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Layout.h"
#include "idr/Conversion/ArrayView.h"
#include "idr/Conversion/IdrPattern.h"
#include "idr/Conversion/Patterns.h"
#include "idr/Conversion/Runtime.h"
#include "idr/Conversion/Words.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Transforms/DialectConversion.h"

using namespace mlir;

namespace idr::conversion {

namespace {

// The address of the byte at `offset` in the buffer.
Value byteAt(OpBuilder &b, Location loc, ValueRange buffer, Value offset) {
  return LLVM::GEPOp::create(b, loc, ptrType(b.getContext()), b.getI8Type(),
                             elementsOf(b, loc, buffer[0]), ArrayRef<LLVM::GEPArg>{offset},
                             LLVM::GEPNoWrapFlags::inbounds);
}

struct LowerBufferLoad : IdrPattern<BufferLoadOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(BufferLoadOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    Type word = this->layouts.components(op.getValue().getType()).front();
    Value addr = byteAt(rewriter, loc, adaptor.getBuffer(), adaptor.getOffset().front());
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
    Value addr = byteAt(rewriter, loc, adaptor.getBuffer(), adaptor.getOffset().front());
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
