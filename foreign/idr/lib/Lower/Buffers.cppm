// idr.lower:buffers: a machine word in a buffer of bytes. The buffer is the
// array cell and its length. The word is at its offset from the first byte,
// where the op's guard found its bytes within that length, or a proof did
// where it removed the guard: the access tests nothing itself. The load and
// the store are the target's own, at alignment 1: the endianness is the
// machine's, and the offset need not be aligned.

export module idr.lower:buffers;

import idr.mlir;
import idr.dialect;
import idr.layout;

import :arrayView;
import :idrPattern;
import :runtime;
import :words;

using namespace mlir;

namespace idr::lower {

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

export void populateBufferPatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                                   layout::Layouts &layouts, Runtime &runtime) {
  patterns.add<LowerBufferLoad, LowerBufferStore>(converter, patterns.getContext(), layouts, runtime);
}

} // namespace idr::lower
