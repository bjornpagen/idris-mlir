// What the folders of the string and big ops, and of double_head and
// int_head, share: each converts its constant operands to runtime values,
// calls the runtime's own C function, which idris-mlir links natively, and
// converts the result back. A primitive has one implementation, at compile
// time and at runtime; nothing here computes one. A total op is not folded
// where the condition of its guard fails on its constants (idr::checkHolds):
// the guard crashes there first, at runtime. The folders themselves (the
// ops' `fold` hooks) are the units of lib/IR/Fold.
#ifndef IDR_IR_FOLD_H
#define IDR_IR_FOLD_H

#include "idr/IR/IdrDialect.h"

// The runtime's C ABI: its strings and bigs.
#include "idris_rt.h"

#include "mlir/IR/Attributes.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/OpDefinition.h"
#include "mlir/IR/Types.h"
#include "llvm/ADT/SmallVector.h"

#include <cstdint>
#include <optional>

namespace idr::fold {

// The owned references one fold holds, released together when it ends.
// Every runtime operation returns an owned reference, even when what it
// returns is one of its arguments (appending the empty string gives the
// other argument, with one more reference), so the scope keeps every
// reference it is given, a repeated one as often as it was given, and
// releases each once; and counts on the context the cells it leaves live,
// read on the thread that folds: the runtime counts by thread, and a fold
// never changes thread. Scopes do not nest on one thread; a nested pair
// would count an inner leak twice.
class Scope {
public:
  explicit Scope(mlir::MLIRContext *c);
  ~Scope();
  Scope(const Scope &) = delete;
  Scope &operator=(const Scope &) = delete;

  const idris_rt_str *str(mlir::StringAttr value);
  idris_rt_big big(BigAttr value);
  const idris_rt_str *keep(const idris_rt_str *s);
  idris_rt_big keep(idris_rt_big b);
  mlir::Attribute attr(const idris_rt_str *s);
  mlir::Attribute attr(idris_rt_big b);

private:
  mlir::MLIRContext *ctx;
  uint64_t liveAtStart;
  llvm::SmallVector<const idris_rt_str *> strings;
  llvm::SmallVector<idris_rt_big> bigs;
};

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
mlir::OpFoldResult strBinary(mlir::MLIRContext *ctx, mlir::Attribute lhs, mlir::Attribute rhs,
                             Fn fn) {
  auto a = mlir::dyn_cast_or_null<mlir::StringAttr>(lhs);
  auto b = mlir::dyn_cast_or_null<mlir::StringAttr>(rhs);
  if (!a || !b)
    return {};
  Scope scope(ctx);
  return fn(scope, scope.str(a), scope.str(b));
}

// `fn` of one constant big; nothing when it is no constant.
template <typename Fn>
mlir::OpFoldResult bigUnary(mlir::MLIRContext *ctx, mlir::Attribute operand, Fn fn) {
  auto a = mlir::dyn_cast_or_null<BigAttr>(operand);
  if (!a)
    return {};
  Scope scope(ctx);
  return fn(scope, scope.big(a));
}

// `op` of two constant bigs; nothing when either is no constant.
mlir::OpFoldResult bigBinary(mlir::MLIRContext *ctx, mlir::Attribute lhs, mlir::Attribute rhs,
                             BigOp op);

// The 64-bit value of an integer operand, extended as the op's signedness
// says.
int64_t extended(mlir::IntegerAttr value, bool isSigned);

// A runtime result modulo 2^64 as an integer of `type`.
mlir::Attribute wrapped(mlir::Type type, int64_t value);

// Whether `predicate` holds of a comparison whose result is `order`
// (negative, zero or positive), as a constant.
mlir::Attribute compared(mlir::MLIRContext *ctx, CmpPredicate predicate, int32_t order);

// The elements of a constant list: a chain of constructors of two fields
// ending in one of none; nothing for any other constant. A run along the
// second field is a stretch of the chain, read a cell at a time and then
// its tail, never through the rest of the run that reading the field would
// build.
std::optional<llvm::SmallVector<mlir::Attribute>> listElements(mlir::Attribute list);

} // namespace idr::fold

namespace idr {

// The string a constant list of characters packs to, or a constant list of
// strings concatenates to, as the runtime builds it; null for any other
// constant.
mlir::Attribute stringOfList(mlir::MLIRContext *context, mlir::Attribute list);

} // namespace idr

#endif // IDR_IR_FOLD_H
