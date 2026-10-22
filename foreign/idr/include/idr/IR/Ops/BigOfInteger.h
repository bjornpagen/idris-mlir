// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A big made of an integer (Spec.Ops.Bigs): how it reads the integer, a
// constant of its class, which the generated code specializes for each such
// op (Generated/BigOfInteger.h.inc: `static constexpr numeric::Signedness
// signedness`), read by BigOfIntegerOpInterface's default, so a reader asks
// the op and lists none. The default names it, so the dialect's header
// includes this before the interfaces.
#ifndef IDR_IR_OPS_BIGOFINTEGER_H
#define IDR_IR_OPS_BIGOFINTEGER_H

#include "idr/IR/Generated/NumericEnums.h.inc"

namespace idr {

template <typename Op>
struct BigOfInteger;

template <typename Op>
numeric::Signedness signednessOfOp(Op) {
  return BigOfInteger<Op>::signedness;
}

} // namespace idr

#endif // IDR_IR_OPS_BIGOFINTEGER_H
