// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s
// idr.shl and idr.shr fold to Idris's meaning for every amount: Scheme's
// ash wrapped to the width, a negative signed amount shifting the other
// way, and from the width up only the fill (0, or -1 for a negative value
// shifted right). A shift by 0 is its value.

// CHECK-LABEL: func.func @signed(
// CHECK-DAG: %[[ZERO:.*]] = arith.constant 0 : i64
// CHECK-DAG: %[[M2:.*]] = arith.constant -2 : i64
// CHECK-DAG: %[[M1:.*]] = arith.constant -1 : i64
// CHECK-DAG: %[[MIN:.*]] = arith.constant -9223372036854775808 : i64
// CHECK-NOT: idr.sh
// CHECK: return %[[ZERO]], %[[M2]], %[[M2]], %[[M1]], %[[MIN]], %[[ZERO]]
func.func @signed() -> (i64, i64, i64, i64, i64, i64) {
  %one = arith.constant 1 : i64
  %m8 = arith.constant -8 : i64
  %c2 = arith.constant 2 : i64
  %cm2 = arith.constant -2 : i64
  %c63 = arith.constant 63 : i64
  %c64 = arith.constant 64 : i64
  %c70 = arith.constant 70 : i64
  // 1 << 64: past the width, 0.
  %a = idr.shl signed %one, %c64 : i64
  // -8 << -2 is -8 >> 2.
  %b = idr.shl signed %m8, %cm2 : i64
  %c = idr.shr signed %m8, %c2 : i64
  // A negative value shifted right past the width is its sign.
  %d = idr.shr signed %m8, %c70 : i64
  // 1 << 63 wraps to the most negative Int.
  %e = idr.shl signed %one, %c63 : i64
  // A positive value shifted right past the width is 0.
  %f = idr.shr signed %one, %c70 : i64
  return %a, %b, %c, %d, %e, %f : i64, i64, i64, i64, i64, i64
}

// CHECK-LABEL: func.func @unsigned(
// CHECK-DAG: %[[A:.*]] = arith.constant -112 : i8
// CHECK-DAG: %[[B:.*]] = arith.constant 25 : i8
// CHECK-DAG: %[[Z:.*]] = arith.constant 0 : i8
// CHECK-NOT: idr.sh
// CHECK: return %[[A]], %[[B]], %[[Z]]
func.func @unsigned() -> (i8, i8, i8) {
  %v = arith.constant 200 : i8
  %c1 = arith.constant 1 : i8
  %c3 = arith.constant 3 : i8
  %c9 = arith.constant 9 : i8
  // 200 << 1 is 400, wrapped to 144 (printed as the i8 -112).
  %a = idr.shl %v, %c1 : i8
  // A right shift of an unsigned value fills with zeros.
  %b = idr.shr %v, %c3 : i8
  %c = idr.shr %v, %c9 : i8
  return %a, %b, %c : i8, i8, i8
}

// CHECK-LABEL: func.func @by_zero(
// CHECK-SAME: %[[X:.*]]: i64
// CHECK-NOT: idr.sh
// CHECK: return %[[X]]
func.func @by_zero(%x: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %r = idr.shl signed %x, %c0 : i64
  return %r : i64
}
