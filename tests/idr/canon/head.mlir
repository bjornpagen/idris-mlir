// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s
// The first character of a string built at runtime.

// CHECK-LABEL: func.func @heads(
// CHECK-SAME: %[[C:.*]]: i32, %[[S:.*]]: !idr.str, %[[X:.*]]: i64, %[[B:.*]]: i16, %[[D:.*]]: f64)
// CHECK-NEXT: %[[I:.*]] = idr.int_head signed %[[X]] : i64
// CHECK-NEXT: %[[U:.*]] = idr.int_head %[[B]] : i16
// CHECK-NEXT: %[[H:.*]] = idr.double_head %[[D]]
// CHECK-NEXT: return %[[C]], %[[I]], %[[U]], %[[H]]
func.func @heads(%c: i32, %s: !idr.str, %x: i64, %b: i16, %d: f64) -> (i32, i32, i32, i32) {
  %t = idr.str.cons %c, %s
  %h0 = idr.str.head %t
  %u = idr.str.show signed %x : i64
  %h1 = idr.str.head %u
  %v = idr.str.show unsigned %b : i16
  %h2 = idr.str.head %v
  %e = idr.str.show %d : f64
  %h3 = idr.str.head %e
  return %h0, %h1, %h2, %h3 : i32, i32, i32, i32
}

// The head of any other string stays, after its guard, which may crash.
// CHECK-LABEL: func.func @other(
// CHECK: %[[G:.*]] = idr.check.nonempty
// CHECK: idr.str.head %[[G]]
func.func @other(%s: !idr.str) -> i32 {
  %g = idr.check.nonempty %s, "head of an empty string" : !idr.str
  %h = idr.str.head %g
  return %h : i32
}
