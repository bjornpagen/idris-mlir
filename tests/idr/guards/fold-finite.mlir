// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s
// The guard of a Double cast to an integer folds to the Double where it is
// a finite constant; then the cast folds too. On NaN or an infinity the
// guard stays, to crash where it runs. A guard of what an identical guard
// already checked folds too.
// CHECK-LABEL: func.func @proving(
// CHECK-NOT: idr.check.finite
// CHECK-NOT: idr.to_int
// CHECK: %[[I:.*]] = arith.constant -2 : i64
// CHECK: return %[[I]]
func.func @proving() -> i64 {
  %d = arith.constant -2.75 : f64
  %g = idr.check.finite %d, "cast of a non-finite Double"
  %i = idr.to_int %g : i64
  return %i : i64
}

// CHECK-LABEL: func.func @failing(
// CHECK: idr.check.finite %{{.*}}, "cast of a non-finite Double"
// CHECK: idr.check.finite %{{.*}}, "cast of a non-finite Double"
// CHECK: return
func.func @failing(%b: !idr.big) -> (i64, !idr.big) {
  %nan = arith.constant 0x7FF8000000000000 : f64
  %g = idr.check.finite %nan, "cast of a non-finite Double"
  %i = idr.to_int %g : i64
  %inf = arith.constant 0xFFF0000000000000 : f64
  %h = idr.check.finite %inf, "cast of a non-finite Double"
  %j = idr.big.from_double %h
  return %i, %j : i64, !idr.big
}

// CHECK-LABEL: func.func @again(
// CHECK-SAME: %[[D:[^:]*]]: f64)
// CHECK: %[[G:.*]] = idr.check.finite %[[D]], "cast of a non-finite Double"
// CHECK-NOT: idr.check.finite
// CHECK: idr.to_int %[[G]] : i64
// CHECK-NOT: idr.check.finite
// CHECK: idr.big.from_double %[[G]]
// CHECK-NOT: idr.check.finite
// CHECK: return
func.func @again(%d: f64) -> (i64, !idr.big) {
  %g = idr.check.finite %d, "cast of a non-finite Double"
  %i = idr.to_int %g : i64
  %h = idr.check.finite %g, "cast of a non-finite Double"
  %j = idr.big.from_double %h
  return %i, %j : i64, !idr.big
}
