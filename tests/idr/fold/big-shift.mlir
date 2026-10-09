// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s
// idr.big.shl and idr.big.shr fold by calling the runtime: a left shift
// multiplies by 2^amount, a right shift is the floor of the quotient, a
// negative amount shifts the other way, and 0 shifted any amount is 0. A
// shift away from zero whose constant would take more static data than a
// constant made at compile time may stays, to run at runtime.

// CHECK-LABEL: func.func @folded(
// CHECK-DAG: %[[M4:.*]] = idr.constant #idr.big<"-4"> : !idr.big
// CHECK-DAG: %[[P64:.*]] = idr.constant #idr.big<"18446744073709551616"> : !idr.big
// CHECK-DAG: %[[ZERO:.*]] = idr.constant #idr.big<"0"> : !idr.big
// CHECK-DAG: %[[M1:.*]] = idr.constant #idr.big<"-1"> : !idr.big
// CHECK-NOT: idr.big.sh
// CHECK: return %[[M4]], %[[M4]], %[[P64]], %[[ZERO]], %[[M1]], %[[ZERO]]
func.func @folded() -> (!idr.big, !idr.big, !idr.big, !idr.big, !idr.big, !idr.big) {
  %m7 = idr.constant #idr.big<"-7"> : !idr.big
  %one = idr.constant #idr.big<"1"> : !idr.big
  %m1 = idr.constant #idr.big<"-1"> : !idr.big
  %c0 = idr.constant #idr.big<"0"> : !idr.big
  %c64 = idr.constant #idr.big<"64"> : !idr.big
  %huge = idr.constant #idr.big<"100000000000000000000"> : !idr.big
  %mhuge = idr.constant #idr.big<"-100000000000000000000"> : !idr.big
  // -7 >> 1 is the floor of -3.5.
  %a = idr.big.shr %m7, %one
  // A negative amount shifts the other way.
  %b = idr.big.shl %m7, %m1
  %c = idr.big.shl %one, %c64
  // 0 moved any amount, and anything moved toward zero by an amount no word
  // holds.
  %d = idr.big.shl %c0, %huge
  %e = idr.big.shr %m1, %huge
  %f = idr.big.shl %one, %mhuge
  return %a, %b, %c, %d, %e, %f : !idr.big, !idr.big, !idr.big, !idr.big, !idr.big, !idr.big
}

// CHECK-LABEL: func.func @too_large(
// CHECK-DAG: idr.big.shl
// CHECK-DAG: idr.big.shr
// CHECK: return
func.func @too_large() -> (!idr.big, !idr.big) {
  %one = idr.constant #idr.big<"1"> : !idr.big
  // One bit past 8 * 2^20.
  %n = idr.constant #idr.big<"8388609"> : !idr.big
  %mn = idr.constant #idr.big<"-18446744073709551616"> : !idr.big
  %a = idr.big.shl %one, %n
  // A right shift by a negative amount grows.
  %b = idr.big.shr %one, %mn
  return %a, %b : !idr.big, !idr.big
}
