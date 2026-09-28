// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s
// rule: IDR-MATCH-6, ELIM-G-15
// IDR-MATCH-6: a string that cannot be empty never takes the case "".

// CHECK-LABEL: func.func @nonempty(
// CHECK-SAME: %[[X:.*]]: i64, %[[C:.*]]: i32, %[[S:.*]]: !idr.str)
// CHECK-DAG: %[[ONE:.*]] = arith.constant 1 : i64
// CHECK-NOT: idr.match_lit
// CHECK: return %[[ONE]], %[[ONE]], %[[ONE]]
func.func @nonempty(%x: i64, %c: i32, %s: !idr.str) -> (i64, i64, i64) {
  %zero = arith.constant 0 : i64
  %one = arith.constant 1 : i64
  %shown = idr.str.show signed %x : i64
  %a = idr.match_lit %shown : !idr.str -> (i64) {
  case "" {
    idr.yield %zero : i64
  }
  default {
    idr.yield %one : i64
  }
  }
  %consed = idr.str.cons %c, %s
  %b = idr.match_lit %consed : !idr.str -> (i64) {
  case "" {
    idr.yield %zero : i64
  }
  default {
    idr.yield %one : i64
  }
  }
  %lit = idr.constant "x" : !idr.str
  %appended = idr.str.append %s, %lit
  %d = idr.match_lit %appended : !idr.str -> (i64) {
  case "" {
    idr.yield %zero : i64
  }
  default {
    idr.yield %one : i64
  }
  }
  return %a, %b, %d : i64, i64, i64
}

// Any other string may be empty; other keys stay.
// CHECK-LABEL: func.func @maybe_empty(
// CHECK: idr.match_lit %{{.*}} : !idr.str -> (i64) {
// CHECK-NEXT: case "" {
// CHECK: idr.match_lit %{{.*}} : !idr.str -> (i64) {
// CHECK-NEXT: case "1" {
// CHECK-NOT: case ""
// CHECK: default
func.func @maybe_empty(%x: i64, %s: !idr.str) -> (i64, i64) {
  %zero = arith.constant 0 : i64
  %one = arith.constant 1 : i64
  %a = idr.match_lit %s : !idr.str -> (i64) {
  case "" {
    idr.yield %zero : i64
  }
  default {
    idr.yield %one : i64
  }
  }
  %shown = idr.str.show signed %x : i64
  %b = idr.match_lit %shown : !idr.str -> (i64) {
  case "1" {
    idr.yield %zero : i64
  }
  case "" {
    idr.yield %x : i64
  }
  default {
    idr.yield %one : i64
  }
  }
  return %a, %b : i64, i64
}
