// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s
// The guard of a divisor folds to the divisor where the divisor shows it is
// not zero: a constant integer, or a constant big, other than zero. On zero
// it stays, to crash where it runs. A guard of what an identical guard
// already checked folds too: its operand is that guard's result.
// CHECK-LABEL: func.func @proving(
// CHECK-NOT: idr.check.nonzero
// CHECK: idr.div signed
// CHECK-NOT: idr.check.nonzero
// CHECK: idr.big.div
// CHECK-NOT: idr.check.nonzero
// CHECK: return
func.func @proving(%x: i64, %b: !idr.big) -> (i64, !idr.big) {
  %seven = arith.constant 7 : i64
  %g = idr.check.nonzero %seven, "division by zero" : i64
  %q = idr.div signed %x, %g : i64
  %three = idr.constant #idr.big<"-3"> : !idr.big
  %h = idr.check.nonzero %three, "division by zero" : !idr.big
  %r = idr.big.div %b, %h
  return %q, %r : i64, !idr.big
}

// CHECK-LABEL: func.func @failing(
// CHECK: idr.check.nonzero %{{.*}}, "division by zero" : i64
// CHECK: idr.check.nonzero %{{.*}}, "division by zero" : !idr.big
// CHECK: return
func.func @failing(%x: i64, %b: !idr.big) -> (i64, !idr.big) {
  %zero = arith.constant 0 : i64
  %g = idr.check.nonzero %zero, "division by zero" : i64
  %q = idr.div signed %x, %g : i64
  %none = idr.constant #idr.big<"0"> : !idr.big
  %h = idr.check.nonzero %none, "division by zero" : !idr.big
  %r = idr.big.div %b, %h
  return %q, %r : i64, !idr.big
}

// CHECK-LABEL: func.func @again(
// CHECK-SAME: %[[X:[^:]*]]: i64, %[[Y:[^:]*]]: i64)
// CHECK: %[[G:.*]] = idr.check.nonzero %[[Y]], "division by zero" : i64
// CHECK-NOT: idr.check.nonzero
// CHECK: idr.div signed %[[X]], %[[G]] : i64
// CHECK-NOT: idr.check.nonzero
// CHECK: idr.mod signed %[[X]], %[[G]] : i64
// CHECK-NOT: idr.check.nonzero
// CHECK: return
func.func @again(%x: i64, %y: i64) -> (i64, i64) {
  %g = idr.check.nonzero %y, "division by zero" : i64
  %q = idr.div signed %x, %g : i64
  %h = idr.check.nonzero %g, "division by zero" : i64
  %m = idr.mod signed %x, %h : i64
  return %q, %m : i64, i64
}
