// RUN: idris-mlir-opt %s -split-input-file --idr-optimize | FileCheck %s
// NEEDS-ACCEPTANCE: the printed form of each root after the optimizer.
// The optimizer inlines a callee as func's inliner does: the callee's body
// replaces the call and its return's operands the call's results, so
// nothing of the callee's return is left. A callee that never returns ends
// in ub.unreachable: inlined into a function body, it ends that body, and
// the code after the call, which no path reaches, goes; in a match region,
// which stays one block, the call stays a call.

// CHECK-LABEL: idr.func @main(
// CHECK-NOT: call
// CHECK: %[[Y:.*]] = arith.addi %{{.*}}, %{{.*}} : i64
// CHECK-NEXT: %[[Z:.*]] = arith.muli %[[Y]], %[[Y]] : i64
idr.func private @add(%a: i64, %b: i64) -> i64 attributes {total} {
  %r = arith.addi %a, %b : i64
  return %r : i64
}
idr.func @main(%w: !idr.world) -> !idr.world {
  %c, %w1 = idr.io.get_byte %w
  %x = arith.extui %c : i32 to i64
  %s = idr.call @add(%x, %x) : (i64, i64) -> i64
  %z = arith.muli %s, %s : i64
  %w2 = idr.io.put_int signed %z, %w1 : i64
  return %w2 : !idr.world
}

// -----

// CHECK-LABEL: idr.func @main(
// CHECK: crash "no"
// CHECK-NEXT: ub.unreachable
// CHECK-NEXT: }
idr.func private @fail(%x: i64) -> i64 attributes {total} {
  idr.crash "no"
  ub.unreachable
}
idr.func @main(%w: !idr.world) -> !idr.world {
  %c, %w1 = idr.io.get_byte %w
  %x = arith.extui %c : i32 to i64
  %r = idr.call @fail(%x) : (i64) -> i64
  %w2 = idr.io.put_int signed %r, %w1 : i64
  return %w2 : !idr.world
}

// -----

// CHECK-LABEL: idr.func @main(
// CHECK: case 0 {
// CHECK-NEXT: %{{.*}} = {{(idr\.)?}}call @fail(
// CHECK-NEXT: idr.yield
idr.func private @fail(%x: i64) -> i64 attributes {total} {
  idr.crash "no"
  ub.unreachable
}
idr.func @main(%w: !idr.world) -> !idr.world {
  %c, %w1 = idr.io.get_byte %w
  %x = arith.extui %c : i32 to i64
  %r = idr.match_lit %x : i64 -> (i64) {
  case 0 {
    %y = idr.call @fail(%x) : (i64) -> i64
    idr.yield %y : i64
  }
  default {
    idr.yield %x : i64
  }
  }
  %w2 = idr.io.put_int signed %r, %w1 : i64
  return %w2 : !idr.world
}
