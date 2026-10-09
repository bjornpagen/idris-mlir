// RUN: idris-mlir-opt %s --idr-effects --canonicalize | FileCheck %s
// An unused call goes when its callee is pure, total and
// cannot crash, and no closure it is given could do otherwise.

func.func private @square(%x: i64) -> i64 attributes {idr.total} {
  %r = arith.muli %x, %x : i64
  return %r : i64
}
func.func private @partial(%x: i64) -> i64 {
  %r = arith.muli %x, %x : i64
  return %r : i64
}
func.func private @divides(%x: i64) -> i64 attributes {idr.total} {
  %y = idr.check.nonzero %x, "division by zero" : i64
  %r = idr.div signed %x, %y : i64
  return %r : i64
}
func.func private @writes(%x: i64, %w: !idr.world) -> !idr.world attributes {idr.total} {
  %c = arith.constant 65 : i32
  %w1 = idr.io.put_char %c, %w
  return %w1 : !idr.world
}
func.func private @applies(%f: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 attributes {idr.total} {
  %r = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
  return %r : i64
}
func.func private @crashes(%x: i64) -> i64 attributes {idr.total} {
  idr.crash "no"
  ub.unreachable
}

// CHECK-LABEL: func.func @main(
// CHECK-SAME: %[[X:.*]]: i64, %[[W:.*]]: !idr.world, %[[G:.*]]: !idr.fn<(i64) -> (i64)>)
// CHECK-NEXT: %[[C:.*]] = idr.constant #idr.closure<@crashes, []>
// CHECK-NEXT: call @partial(%[[X]])
// CHECK-NEXT: call @divides(%[[X]])
// CHECK-NEXT: %[[W1:.*]] = call @writes(%[[X]], %[[W]])
// CHECK-NEXT: call @applies(%[[C]], %[[X]])
// CHECK-NEXT: call @applies(%[[G]], %[[X]])
// CHECK-NEXT: return %[[W1]]
func.func @main(%x: i64, %w: !idr.world, %g: !idr.fn<(i64) -> (i64)>) -> !idr.world {
  %a = func.call @square(%x) : (i64) -> i64
  %b = func.call @partial(%x) : (i64) -> i64
  %c = func.call @divides(%x) : (i64) -> i64
  %w1 = func.call @writes(%x, %w) : (i64, !idr.world) -> !idr.world
  %sq = idr.constant #idr.closure<@square, []> : !idr.fn<(i64) -> (i64)>
  %d = func.call @applies(%sq, %x) : (!idr.fn<(i64) -> (i64)>, i64) -> i64
  %cr = idr.constant #idr.closure<@crashes, []> : !idr.fn<(i64) -> (i64)>
  %e = func.call @applies(%cr, %x) : (!idr.fn<(i64) -> (i64)>, i64) -> i64
  %f = func.call @applies(%g, %x) : (!idr.fn<(i64) -> (i64)>, i64) -> i64
  return %w1 : !idr.world
}
