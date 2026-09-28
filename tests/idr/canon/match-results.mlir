// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s
// rule: IDR-MATCH-5, IDR-MATCH-6
// Results no one uses are dropped, and a result that every region yields
// from the same outer value is that value (upstream's region patterns).

idr.data @B {
  idr.ctor @F tag 0 () {quantities = []}
  idr.ctor @T tag 1 () {quantities = []}
}

// CHECK-LABEL: func.func @unused(
// CHECK: %[[R:.*]] = idr.match %{{.*}} : !idr.data<@B> -> (i64) {
// CHECK: idr.yield %{{.*}} : i64
// CHECK: return %[[R]] : i64
func.func @unused(%b: !idr.data<@B>, %x: i64, %y: i64) -> i64 {
  %r:2 = idr.match %b : !idr.data<@B> -> (i64, i64) {
  case @F() {
    %s = arith.addi %x, %y : i64
    idr.yield %s, %x : i64, i64
  }
  case @T() {
    %s = arith.subi %x, %y : i64
    idr.yield %s, %y : i64, i64
  }
  }
  return %r#0 : i64
}

// CHECK-LABEL: func.func @same(
// CHECK-SAME: %{{.*}}: !idr.data<@B>, %[[X:.*]]: i64, %{{.*}}: i32)
// CHECK: return %[[X]] : i64
func.func @same(%b: !idr.data<@B>, %x: i64, %c: i32) -> i64 {
  %r = idr.match %b : !idr.data<@B> -> (i64) {
  case @F() {
    idr.yield %x : i64
  }
  case @T() {
    idr.yield %x : i64
  }
  }
  return %r : i64
}

// A match without effects whose results are unused is dead code; one that
// may crash is not (SEM-EVAL-4).
// CHECK-LABEL: func.func @dead(
// CHECK-NOT: idr.match_lit %{{.*}} : i64 -> (i64)
// CHECK: idr.match_lit %{{.*}} : i64 -> () {
// CHECK: idr.crash
// CHECK: return
func.func @dead(%n: i64) {
  %a = idr.match_lit %n : i64 -> (i64) {
  case 0 {
    idr.yield %n : i64
  }
  default {
    %m = arith.muli %n, %n : i64
    idr.yield %m : i64
  }
  }
  %b = idr.match_lit %n : i64 -> (i64) {
  case 0 {
    idr.yield %n : i64
  }
  default {
    idr.crash "no"
    ub.unreachable
  }
  }
  return
}
