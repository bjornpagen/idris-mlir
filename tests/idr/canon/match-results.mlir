// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s
// RUN: idris-mlir-opt %s --canonicalize=test-convergence=true -o /dev/null
// Results no one uses are dropped, and a result that every region yields
// from the same outer value is that value (upstream's region patterns).


// CHECK-LABEL: idr.func private @unused(
// CHECK: %[[R:.*]] = {{(idr\.)?}}match %{{.*}} : !B -> (i64) {
// CHECK: idr.yield %{{.*}} : i64
// CHECK: return %[[R]] : i64
!B = !idr.data<"B", plain [@F(), @T()]>
idr.func private @unused(%b: !B, %x: i64, %y: i64) -> i64 {
  %r:2 = idr.match %b : !B -> (i64, i64) {
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

// CHECK-LABEL: idr.func private @same(
// CHECK-SAME: %{{.*}}: !B, %[[X:.*]]: i64, %{{.*}}: i32)
// CHECK: return %[[X]] : i64
idr.func private @same(%b: !B, %x: i64, %c: i32) -> i64 {
  %r = idr.match %b : !B -> (i64) {
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
// may crash is not: a crash is an effect.
// CHECK-LABEL: idr.func private @dead(
// CHECK-NOT: {{(idr\.| )match_lit }}%{{.*}} : i64 -> (i64)
// CHECK: match_lit %{{.*}} : i64 -> () {
// CHECK: crash
// CHECK: return
idr.func private @dead(%n: i64) {
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
