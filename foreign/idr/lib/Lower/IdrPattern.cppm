// idr.lower:idrPattern: the base of phase 2's patterns: the layouts and the
// runtime they lower with.
export module idr.lower:idrPattern;

import idr.mlir;
import idr.layout;

import :runtime;

export namespace idr::lower {

// Each pattern instantiates the template, so its body is here.
template <typename OpT>
struct IdrPattern : mlir::OpConversionPattern<OpT> {
  IdrPattern(const mlir::TypeConverter &converter, mlir::MLIRContext *ctx, layout::Layouts &l,
             Runtime &r)
      : mlir::OpConversionPattern<OpT>(converter, ctx), layouts(l), runtime(r) {}
  layout::Layouts &layouts;
  Runtime &runtime;
};

// An op whose meaning is its operand. Linearity, a view, a forgotten
// exclusive grade and a natural as the Integer it is have no runtime form,
// so the value is itself.
template <typename OpT>
struct LowerAsItself : IdrPattern<OpT> {
  using IdrPattern<OpT>::IdrPattern;
  mlir::LogicalResult matchAndRewrite(OpT op, typename IdrPattern<OpT>::OneToNOpAdaptor adaptor,
                                      mlir::ConversionPatternRewriter &rewriter) const override {
    mlir::ValueRange value = adaptor.getOperands().front();
    rewriter.replaceOpWithMultiple(op, {llvm::SmallVector<mlir::Value>(value)});
    return mlir::success();
  }
};

} // namespace idr::lower
