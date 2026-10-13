// RUN: idris-mlir-opt %s --idr-effects --canonicalize | FileCheck %s
// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s --check-prefix=UNWRITTEN
// RUN: idris-mlir-opt %s --idr-effects --canonicalize=test-convergence=true -o /dev/null
// An unused call goes when its callee is pure, total and
// cannot crash, and no closure it is given could do otherwise. What a call
// may do is its own effects, which idr-effects writes from its callee's and
// the closures it is passed; a call it has not written may do anything, so
// canonicalize alone keeps every call.
// UNWRITTEN-LABEL: idr.func @main(
// UNWRITTEN: call @square(

idr.func private @square(%x: i64) -> i64 attributes {total} {
  %r = arith.muli %x, %x : i64
  return %r : i64
}
idr.func private @partial(%x: i64) -> i64 {
  %r = arith.muli %x, %x : i64
  return %r : i64
}
idr.func private @divides(%x: i64) -> i64 attributes {total} {
  %y = idr.check.nonzero %x, "division by zero" : i64
  %r = idr.div signed %x, %y : i64
  return %r : i64
}
idr.func private @writes(%x: i64, %w: !idr.world) -> !idr.world attributes {total} {
  %c = arith.constant 65 : i32
  %w1 = idr.io.put_char %c, %w
  return %w1 : !idr.world
}
idr.func private @applies(%f: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 attributes {total} {
  %r = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
  return %r : i64
}
idr.func private @crashes(%x: i64) -> i64 attributes {total} {
  idr.crash "no"
  ub.unreachable
}

// CHECK-LABEL: idr.func @main(
// CHECK-SAME: %[[X:.*]]: i64, %[[W:.*]]: !idr.world, %[[G:.*]]: !idr.fn<(i64) -> i64>)
// CHECK-NEXT: %[[C:.*]] = {{(idr\.)?}}constant #idr.closure<@crashes, []>
// CHECK-NEXT: call @partial(%[[X]])
// CHECK-NEXT: call @divides(%[[X]])
// CHECK-NEXT: %[[W1:.*]] = call @writes(%[[X]], %[[W]])
// CHECK-NEXT: call @applies(%[[C]], %[[X]])
// CHECK-NEXT: call @applies(%[[G]], %[[X]])
// CHECK-NEXT: return %[[W1]]
idr.func @main(%x: i64, %w: !idr.world, %g: !idr.fn<(i64) -> (i64)>) -> !idr.world {
  %a = idr.call @square(%x) : (i64) -> i64
  %b = idr.call @partial(%x) : (i64) -> i64
  %c = idr.call @divides(%x) : (i64) -> i64
  %w1 = idr.call @writes(%x, %w) : (i64, !idr.world) -> !idr.world
  %sq = idr.constant #idr.closure<@square, []> : !idr.fn<(i64) -> (i64)>
  %d = idr.call @applies(%sq, %x) : (!idr.fn<(i64) -> (i64)>, i64) -> i64
  %cr = idr.constant #idr.closure<@crashes, []> : !idr.fn<(i64) -> (i64)>
  %e = idr.call @applies(%cr, %x) : (!idr.fn<(i64) -> (i64)>, i64) -> i64
  %f = idr.call @applies(%g, %x) : (!idr.fn<(i64) -> (i64)>, i64) -> i64
  return %w1 : !idr.world
}
