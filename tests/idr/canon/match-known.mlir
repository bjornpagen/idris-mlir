// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s
// A match whose taken region is known is replaced by that region: the
// scrutinee is a constant or built by idr.con, or one region is left. The
// region's arguments become the constructor's fields.

idr.data @Shape {
  idr.ctor @Circle tag 0 (f64)
  idr.ctor @Rect tag 1 (f64, f64)
}

// CHECK-LABEL: func.func @of_con(
// CHECK-SAME: %[[W:.*]]: f64, %[[H:.*]]: f64)
// CHECK-NEXT: %[[A:.*]] = arith.mulf %[[W]], %[[H]] : f64
// CHECK-NEXT: return %[[A]]
func.func @of_con(%w: f64, %h: f64) -> f64 {
  %s = idr.con @Shape::@Rect(%w, %h) : (f64, f64) -> !idr.data<@Shape>
  %r = idr.match %s : !idr.data<@Shape> -> (f64) {
  case @Circle(%x: f64) {
    %a = arith.mulf %x, %x : f64
    idr.yield %a : f64
  }
  case @Rect(%x: f64, %y: f64) {
    %a = arith.mulf %x, %y : f64
    idr.yield %a : f64
  }
  }
  return %r : f64
}

// CHECK-LABEL: func.func @of_constant(
// CHECK-NEXT: %[[C:.*]] = arith.constant 4.000000e+00 : f64
// CHECK-NEXT: return %[[C]]
func.func @of_constant() -> f64 {
  %s = idr.constant #idr.con<@Shape::@Circle, [2.0 : f64]> : !idr.data<@Shape>
  %r = idr.match %s : !idr.data<@Shape> -> (f64) {
  case @Circle(%x: f64) {
    %a = arith.mulf %x, %x : f64
    idr.yield %a : f64
  }
  case @Rect(%x: f64, %y: f64) {
    %a = arith.mulf %x, %y : f64
    idr.yield %a : f64
  }
  }
  return %r : f64
}

// A constructor without a case takes the default.
// CHECK-LABEL: func.func @to_default(
// CHECK-NEXT: %[[C:.*]] = arith.constant 0.000000e+00 : f64
// CHECK-NEXT: return %[[C]]
func.func @to_default(%w: f64) -> f64 {
  %s = idr.con @Shape::@Rect(%w, %w) : (f64, f64) -> !idr.data<@Shape>
  %r = idr.match %s : !idr.data<@Shape> -> (f64) {
  case @Circle(%x: f64) {
    idr.yield %x : f64
  }
  default {
    %z = arith.constant 0.0 : f64
    idr.yield %z : f64
  }
  }
  return %r : f64
}

// One region left: the others are impossible, so it runs, and its fields
// are read from the scrutinee.
// CHECK-LABEL: func.func @single(
// CHECK-SAME: %[[S:.*]]: !idr.data<@Shape>)
// CHECK-NEXT: %[[X:.*]] = idr.field %[[S]][@Circle, 0] : !idr.data<@Shape> -> f64
// CHECK-NEXT: %[[A:.*]] = arith.mulf %[[X]], %[[X]] : f64
// CHECK-NEXT: return %[[A]]
func.func @single(%s: !idr.data<@Shape>) -> f64 {
  %r = idr.match %s : !idr.data<@Shape> -> (f64) {
  case @Circle(%x: f64) {
    %a = arith.mulf %x, %x : f64
    idr.yield %a : f64
  }
  }
  return %r : f64
}

// A region that crashes is never inlined into the middle of a block.
// CHECK-LABEL: func.func @crashes(
// CHECK: idr.match
// CHECK: idr.crash "no"
// CHECK-NEXT: ub.unreachable
func.func @crashes(%w: f64) -> f64 {
  %s = idr.con @Shape::@Rect(%w, %w) : (f64, f64) -> !idr.data<@Shape>
  %r = idr.match %s : !idr.data<@Shape> -> (f64) {
  case @Circle(%x: f64) {
    idr.yield %x : f64
  }
  case @Rect(%x: f64, %y: f64) {
    idr.crash "no"
    ub.unreachable
  }
  }
  return %r : f64
}

// Literals: integers, strings and bigs.
// CHECK-LABEL: func.func @literals(
// CHECK-DAG: %[[TWO:.*]] = arith.constant 2 : i64
// CHECK-DAG: %[[THREE:.*]] = arith.constant 3 : i64
// CHECK-DAG: %[[FOUR:.*]] = arith.constant 4 : i64
// CHECK-NOT: idr.match_lit
// CHECK: return %[[TWO]], %[[THREE]], %[[FOUR]]
func.func @literals() -> (i64, i64, i64) {
  %n = arith.constant 7 : i64
  %s = idr.constant "b" : !idr.str
  %g = idr.constant #idr.big<"99999999999999999999"> : !idr.big
  %one = arith.constant 1 : i64
  %two = arith.constant 2 : i64
  %three = arith.constant 3 : i64
  %four = arith.constant 4 : i64
  %a = idr.match_lit %n : i64 -> (i64) {
  case 7 {
    idr.yield %two : i64
  }
  default {
    idr.yield %one : i64
  }
  }
  %b = idr.match_lit %s : !idr.str -> (i64) {
  case "a" {
    idr.yield %one : i64
  }
  case "b" {
    idr.yield %three : i64
  }
  default {
    idr.yield %one : i64
  }
  }
  %c = idr.match_lit %g : !idr.big -> (i64) {
  case #idr.big<"0"> {
    idr.yield %one : i64
  }
  default {
    idr.yield %four : i64
  }
  }
  return %a, %b, %c : i64, i64, i64
}
