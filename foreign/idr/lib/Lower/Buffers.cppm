// idr.lower:buffers: a machine word in a buffer of bytes. The buffer is the
// array cell and its length. The address of the word is idris_rt_buffer_at,
// which crashes unless the word's bytes lie in that length. The load and
// the store are the target's own, at alignment 1: the endianness is the
// machine's, and the offset need not be aligned, as Chez's
// native-endianness bytevector access is.

export module idr.lower:buffers;

import idr.mlir;
import idr.dialect;
import idr.layout;

import :idrPattern;
import :runtime;
import :words;

using namespace mlir;

namespace idr::lower {

namespace {

// The number of bytes of the word the op reads or writes. The verifier has
// kept it to i8, i16, i32, i64 or f64.
unsigned byteWidth(Type type) {
  type = unrestricted(type);
  if (auto integer = dyn_cast<IntegerType>(type))
    return integer.getWidth() / 8;
  return 8;
}

// The address of `bytes` at `offset` in the buffer, or a crash.
Value at(OpBuilder &b, Location loc, Runtime &runtime, ValueRange buffer, Value offset,
         unsigned bytes) {
  return runtime.call(b, loc, "idris_rt_buffer_at", ptrType(b.getContext()),
                      ValueRange{buffer[0], buffer[1], offset, i64Constant(b, loc, bytes)});
}

struct LowerBufferLoad : IdrPattern<BufferLoadOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(BufferLoadOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    Type word = this->layouts.components(op.getValue().getType()).front();
    Value addr = at(rewriter, loc, this->runtime, adaptor.getBuffer(), adaptor.getOffset().front(),
                    byteWidth(op.getValue().getType()));
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
    Value addr = at(rewriter, loc, this->runtime, adaptor.getBuffer(), adaptor.getOffset().front(),
                    byteWidth(op.getValue().getType()));
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
