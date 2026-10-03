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

} // namespace idr::lower
