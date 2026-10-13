// RUN: idris-mlir-opt %s --idr-inline | FileCheck %s
// The inliner takes in a callee as func's does: the callee's body replaces
// the call and its return's operands the call's results, so nothing of the
// callee's return is left. A callee that never returns ends in
// ub.unreachable: inlined into a function body, it ends that body, and the
// code after the call, which no path reaches, goes; in a match region,
// which stays one block, the call stays a call.

// CHECK-LABEL: idr.func @caller(
// CHECK-NOT: call
// CHECK: %[[Y:.*]] = arith.addi %{{.*}}, %{{.*}} : i64
// CHECK-NEXT: %[[Z:.*]] = arith.muli %[[Y]], %[[Y]] : i64
// CHECK-NEXT: return %[[Z]] : i64
// CHECK-NEXT: }
idr.func private @add(%a: i64, %b: i64) -> i64 attributes {total, effects = #idr.effects<none>} {
  %r = arith.addi %a, %b : i64
  return %r : i64
}
idr.func @caller(%x: i64, %y: i64) -> i64 {
  %s = idr.call @add(%x, %y) : (i64, i64) -> i64
  %z = arith.muli %s, %s : i64
  return %z : i64
}

// CHECK-LABEL: idr.func @body(
// CHECK-NEXT: crash "no"
// CHECK-NEXT: ub.unreachable
// CHECK-NEXT: }
// CHECK-LABEL: idr.func @region(
// CHECK: case 0 {
// CHECK-NEXT: %{{.*}} = idr.call @fail(
// CHECK-NEXT: idr.yield
idr.func private @fail(%x: i64) -> i64 attributes {total, effects = #idr.effects<crash>} {
  idr.crash "no"
  ub.unreachable
}
idr.func @body(%x: i64) -> i64 {
  %r = idr.call @fail(%x) : (i64) -> i64
  return %r : i64
}
idr.func @region(%b: i64, %x: i64) -> i64 {
  %r = idr.match_lit %b : i64 -> (i64) {
  case 0 {
    %y = idr.call @fail(%x) : (i64) -> i64
    idr.yield %y : i64
  }
  default {
    idr.yield %x : i64
  }
  }
  return %r : i64
}
