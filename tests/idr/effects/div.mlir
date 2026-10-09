// RUN: idris-mlir-opt %s --canonicalize --cse --loop-invariant-code-motion | FileCheck %s
// A division is its divisor's guard, which may crash, and the division
// itself, which only computes. A dead division goes, and its guard stays
// unless the divisor is a nonzero constant. The guard is not speculated,
// and the division never runs before it: it takes the guard's result. A
// division by a nonzero constant needs no guard, and may move anywhere.

// CHECK-LABEL: func.func @dead(
// CHECK-SAME: %[[X:.*]]: i64, %[[Y:.*]]: i64)
// CHECK-NEXT: idr.check.nonzero %[[Y]], "division by zero" : i64
// CHECK-NEXT: return %[[X]]
func.func @dead(%x: i64, %y: i64) -> i64 {
  %c3 = arith.constant 3 : i64
  %y1 = idr.check.nonzero %y, "division by zero" : i64
  %q = idr.div signed %x, %y1 : i64
  %c31 = idr.check.nonzero %c3, "division by zero" : i64
  %s = idr.div signed %x, %c31 : i64
  %c32 = idr.check.nonzero %c3, "division by zero" : i64
  %r = idr.mod %x, %c32 : i64
  return %x : i64
}

// CHECK-LABEL: func.func @guarded(
// CHECK: scf.if
// CHECK-NEXT: %[[G:.*]] = idr.check.nonzero
// CHECK-NEXT: idr.div signed %{{.*}}, %[[G]]
func.func @guarded(%b: i1, %x: i64, %y: i64) -> i64 {
  %r = scf.if %b -> i64 {
    %y1 = idr.check.nonzero %y, "division by zero" : i64
    %q = idr.div signed %x, %y1 : i64
    scf.yield %q : i64
  } else {
    scf.yield %x : i64
  }
  return %r : i64
}

// A loop-invariant division leaves the loop only when it cannot crash.
// CHECK-LABEL: func.func @invariant(
// CHECK: idr.div signed %{{.*}}, %{{.*}} : i64
// CHECK: scf.for
// CHECK: %[[G:.*]] = idr.check.nonzero
// CHECK: idr.mod signed %{{.*}}, %[[G]]
// CHECK: scf.yield
func.func @invariant(%x: i64, %y: i64, %n: index) -> i64 {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c7 = arith.constant 7 : i64
  %zero = arith.constant 0 : i64
  %r = scf.for %i = %c0 to %n step %c1 iter_args(%acc = %zero) -> (i64) {
    %q = idr.div signed %x, %c7 : i64
    %y1 = idr.check.nonzero %y, "division by zero" : i64
    %m = idr.mod signed %x, %y1 : i64
    %s = arith.addi %q, %m : i64
    %t = arith.addi %acc, %s : i64
    scf.yield %t : i64
  }
  return %r : i64
}
