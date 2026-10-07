// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s
// A match whose taken region is known is replaced by that region. The
// replacement moves the region's yield into the enclosing block before
// reading which operands the yield forwards, and that block may be an
// array loop. A generate stores the yielded word, so it forwards nothing;
// the operands forwarded are still the match's results.

idr.data @Shape {
  idr.ctor @Circle (f64)
  idr.ctor @Rect (f64, f64)
}

// CHECK-LABEL: func.func @lit_in_generate(
// CHECK-SAME: %[[N:.*]]: i64, %[[FILL:.*]]: i64, %[[W:.*]]: !idr.world)
// CHECK: idr.array.generate %[[N]], %[[FILL]], %[[W]] : i64 -> memref<?xi64> (%[[I:.*]]: i64) {
// CHECK-NEXT: idr.yield %[[I]] : i64
// CHECK-NOT: idr.match
func.func @lit_in_generate(%n: i64, %fill: i64, %w: !idr.world) -> (memref<?xi64>, !idr.world) {
  %c = arith.constant 1 : i64
  %a, %w1 = idr.array.generate %n, %fill, %w : i64 -> memref<?xi64> (%i: i64) {
    %r = idr.match_lit %c : i64 -> (i64) {
    case 1 {
      idr.yield %i : i64
    }
    default {
      idr.yield %fill : i64
    }
    }
    idr.yield %r : i64
  }
  return %a, %w1 : memref<?xi64>, !idr.world
}

// CHECK-LABEL: func.func @match_in_generate(
// CHECK-SAME: %[[N:.*]]: i64, %[[FILL:.*]]: f64, %[[S:.*]]: !idr.data<@Shape>, %[[W:.*]]: !idr.world)
// CHECK: idr.array.generate %[[N]], %[[FILL]], %[[W]] : f64 -> memref<?xf64> (%{{.*}}: i64) {
// CHECK-NEXT: %[[X:.*]] = idr.field %[[S]][@Circle, 0] : !idr.data<@Shape> -> f64
// CHECK-NEXT: idr.yield %[[X]] : f64
// CHECK-NOT: idr.match
func.func @match_in_generate(%n: i64, %fill: f64, %s: !idr.data<@Shape>, %w: !idr.world) -> (memref<?xf64>, !idr.world) {
  %a, %w1 = idr.array.generate %n, %fill, %w : f64 -> memref<?xf64> (%i: i64) {
    %r = idr.match %s : !idr.data<@Shape> -> (f64) {
    case @Circle(%x: f64) {
      idr.yield %x : f64
    }
    }
    idr.yield %r : f64
  }
  return %a, %w1 : memref<?xf64>, !idr.world
}

// CHECK-LABEL: func.func @lit_in_fold(
// CHECK-SAME: %[[A:.*]]: memref<?xi64>, %[[INIT:.*]]: i64, %[[W:.*]]: !idr.world)
// CHECK: idr.array.fold %[[A]], %[[INIT]], %[[W]] : memref<?xi64>, i64 -> i64 (%[[ACC:.*]]: i64, %{{.*}}: i64, %{{.*}}: i64) {
// CHECK-NEXT: idr.yield %[[ACC]] : i64
// CHECK-NOT: idr.match
func.func @lit_in_fold(%a: memref<?xi64>, %init: i64, %w: !idr.world) -> (i64, !idr.world) {
  %c = arith.constant 1 : i64
  %s, %w1 = idr.array.fold %a, %init, %w : memref<?xi64>, i64 -> i64 (%acc: i64, %x: i64, %i: i64) {
    %r = idr.match_lit %c : i64 -> (i64) {
    case 1 {
      idr.yield %acc : i64
    }
    default {
      idr.yield %x : i64
    }
    }
    idr.yield %r : i64
  }
  return %s, %w1 : i64, !idr.world
}
