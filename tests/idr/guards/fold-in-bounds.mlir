// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s
// The guard of an index folds to the index where both it and the length
// are constants and the index is at least 0 and below the length; then the
// character at it folds too. An index at the length, or below 0, keeps its
// guard, to crash where it runs. A guard of what an identical guard, of the
// same length, already checked folds too.
// CHECK-LABEL: func.func @proving(
// CHECK-NOT: idr.check.in_bounds
// CHECK-NOT: idr.str.index
// CHECK: %[[C:.*]] = arith.constant 99 : i32
// CHECK: return %[[C]]
func.func @proving() -> i32 {
  %abc = idr.constant "abc" : !idr.str
  %two = arith.constant 2 : i64
  %n = idr.str.length %abc
  %g = idr.check.in_bounds %two, %n, "string index out of range"
  %c = idr.str.index %abc, %g
  return %c : i32
}

// CHECK-LABEL: func.func @failing(
// CHECK: idr.check.in_bounds %{{.*}}, %{{.*}}, "string index out of range"
// CHECK: idr.check.in_bounds %{{.*}}, %{{.*}}, "string index out of range"
// CHECK: return
func.func @failing() -> (i32, i32) {
  %abc = idr.constant "abc" : !idr.str
  %three = arith.constant 3 : i64
  %below = arith.constant -1 : i64
  %n = idr.str.length %abc
  %g = idr.check.in_bounds %three, %n, "string index out of range"
  %c = idr.str.index %abc, %g
  %h = idr.check.in_bounds %below, %n, "string index out of range"
  %d = idr.str.index %abc, %h
  return %c, %d : i32, i32
}

// CHECK-LABEL: func.func @again(
// CHECK-SAME: %[[S:[^:]*]]: !idr.str, %[[I:[^:]*]]: i64)
// CHECK: %[[N:.*]] = idr.str.length %[[S]]
// CHECK: %[[G:.*]] = idr.check.in_bounds %[[I]], %[[N]], "string index out of range"
// CHECK-NOT: idr.check.in_bounds
// CHECK: idr.str.index %[[S]], %[[G]]
// CHECK-NOT: idr.check.in_bounds
// CHECK: idr.str.index %[[S]], %[[G]]
// CHECK-NOT: idr.check.in_bounds
// CHECK: return
func.func @again(%s: !idr.str, %i: i64) -> (i32, i32) {
  %n = idr.str.length %s
  %g = idr.check.in_bounds %i, %n, "string index out of range"
  %c = idr.str.index %s, %g
  %h = idr.check.in_bounds %g, %n, "string index out of range"
  %d = idr.str.index %s, %h
  return %c, %d : i32, i32
}
