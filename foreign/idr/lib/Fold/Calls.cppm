// idr.fold:calls: a runtime operation on constant operands.
module;
// The runtime's C ABI: its strings and bigs.
#include "idris_rt.h"

export module idr.fold:calls;

import idr.mlir;
import idr.dialect;

import :scope;

using namespace mlir;

export namespace idr::fold {

// `fn` of the string `operand`, in a scope of its own; nothing when the
// operand is no constant string.
template <typename Fn>
mlir::OpFoldResult strUnary(mlir::MLIRContext *ctx, mlir::Attribute operand, Fn fn) {
  auto s = mlir::dyn_cast_or_null<mlir::StringAttr>(operand);
  if (!s)
    return {};
  Scope scope(ctx);
  return fn(scope, scope.str(s));
}

using BigOp = idris_rt_big (*)(idris_rt_big, idris_rt_big);

// `fn` of two constant strings; nothing when either is no constant.
template <typename Fn>
OpFoldResult strBinary(MLIRContext *ctx, Attribute lhs, Attribute rhs, Fn fn) {
  auto a = dyn_cast_or_null<StringAttr>(lhs);
  auto b = dyn_cast_or_null<StringAttr>(rhs);
  if (!a || !b)
    return {};
  Scope scope(ctx);
  return fn(scope, scope.str(a), scope.str(b));
}

// `fn` of one constant big; nothing when it is no constant.
template <typename Fn>
OpFoldResult bigUnary(MLIRContext *ctx, Attribute operand, Fn fn) {
  auto a = dyn_cast_or_null<BigAttr>(operand);
  if (!a)
    return {};
  Scope scope(ctx);
  return fn(scope, scope.big(a));
}

// `op` of two constant bigs; nothing when either is no constant.
OpFoldResult bigBinary(MLIRContext *ctx, Attribute lhs, Attribute rhs, BigOp op) {
  auto a = dyn_cast_or_null<BigAttr>(lhs), b = dyn_cast_or_null<BigAttr>(rhs);
  if (!a || !b)
    return {};
  Scope scope(ctx);
  return scope.attr(op(scope.big(a), scope.big(b)));
}

// Division by zero crashes; the runtime's zero is the word 1.
OpFoldResult bigDivision(MLIRContext *ctx, Attribute lhs, Attribute rhs, BigOp op) {
  auto a = dyn_cast_or_null<BigAttr>(lhs), b = dyn_cast_or_null<BigAttr>(rhs);
  if (!a || !b)
    return {};
  Scope scope(ctx);
  idris_rt_big divisor = scope.big(b);
  if (idris_rt_big_cmp(divisor, scope.keep(idris_rt_big_from_int_s(0))) == 0)
    return {};
  return scope.attr(op(scope.big(a), divisor));
}

} // namespace idr::fold
