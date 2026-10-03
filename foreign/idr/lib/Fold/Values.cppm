// idr.fold:values: an op's constant integers as the runtime takes them, and
// the runtime's results as constants.
export module idr.fold:values;

import idr.mlir;
import idr.dialect;

using namespace mlir;

export namespace idr::fold {

// The 64-bit value of an integer operand, extended as the op's signedness
// says.
int64_t extended(IntegerAttr value, bool isSigned) {
  return isSigned ? value.getValue().getSExtValue()
                  : static_cast<int64_t>(value.getValue().getZExtValue());
}

// A runtime result modulo 2^64 as an integer of `type`.
Attribute wrapped(Type type, int64_t value) {
  unsigned width = type.getIntOrFloatBitWidth();
  return IntegerAttr::get(type, APInt(width, static_cast<uint64_t>(value), /*isSigned=*/false,
                                      /*implicitTrunc=*/true));
}

// Whether `predicate` holds of a comparison whose result is `order`
// (negative, zero or positive), as a constant.
Attribute compared(MLIRContext *ctx, CmpPredicate predicate, int32_t order) {
  bool holds = false;
  switch (predicate) {
  case CmpPredicate::eq:
    holds = order == 0;
    break;
  case CmpPredicate::lt:
    holds = order < 0;
    break;
  case CmpPredicate::lte:
    holds = order <= 0;
    break;
  case CmpPredicate::gt:
    holds = order > 0;
    break;
  case CmpPredicate::gte:
    holds = order >= 0;
    break;
  }
  return BoolAttr::get(ctx, holds);
}

} // namespace idr::fold
