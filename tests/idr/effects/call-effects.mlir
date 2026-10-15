// RUN: idris-mlir-opt %s --idr-effects --cse --canonicalize | FileCheck %s
// idr-effects writes on each call what its callee may do, and the call
// answers MemoryEffectOpInterface from that, so the upstream passes treat
// a call as they treat any op: cse merges two calls of a pure total
// function on the same arguments, canonicalize erases a call whose results
// are unused when it only computes, and a call of a function that may
// crash, perform IO or not return stays, each time it is made. A
// result that is not a scalar is a fresh value the call allocates: two
// such calls stay apart (each makes its own cell) and an unused one goes.
// CHECK-LABEL: idr.func private @main(
// CHECK-SAME: %[[X:[^:]*]]: i64, %[[W:[^:]*]]: !idr.world
// CHECK: %[[S:.*]] = call @square(%[[X]])
// CHECK-NOT: call @square
// CHECK-NOT: call @unused
// CHECK: %[[B1:.*]] = call @boxes(%[[X]])
// CHECK: %[[B2:.*]] = call @boxes(%[[X]])
// CHECK: %[[C1:.*]] = call @crashes(%[[X]])
// CHECK: %[[C2:.*]] = call @crashes(%[[X]])
// CHECK: %[[P1:.*]] = call @partial(%[[X]])
// CHECK: %[[P2:.*]] = call @partial(%[[X]])
// CHECK: %[[W1:.*]] = call @writes(%[[X]], %[[W]])
// CHECK: %[[W2:.*]] = call @writes(%[[X]], %[[W1]])
// CHECK: return %[[S]], %[[S]], %[[B1]], %[[B2]], %[[C1]], %[[C2]], %[[P1]], %[[P2]], %[[W2]]
!Box = !idr.data<"Box", plain [@MkBox(i64)]>
idr.func private @square(%x: i64) -> i64 attributes {total} {
  %r = arith.muli %x, %x : i64
  return %r : i64
}
idr.func private @unused(%x: i64) -> i64 attributes {total} {
  %r = arith.addi %x, %x : i64
  return %r : i64
}
idr.func private @boxes(%x: i64) -> !Box attributes {total} {
  %b = idr.con @MkBox(%x) : (i64) -> !Box
  return %b : !Box
}
idr.func private @crashes(%x: i64) -> i64 attributes {total} {
  %y = idr.check.nonzero %x, "division by zero" : i64
  %r = idr.div signed %x, %y : i64
  return %r : i64
}
idr.func private @partial(%x: i64) -> i64 {
  %r = arith.muli %x, %x : i64
  return %r : i64
}
idr.func private @writes(%x: i64, %w: !idr.world) -> !idr.world attributes {total} {
  %c = arith.constant 65 : i32
  %w1 = idr.io.put_char %c, %w
  return %w1 : !idr.world
}
idr.func private @main(%x: i64, %w: !idr.world) -> (i64, i64, !Box, !Box, i64, i64, i64, i64, !idr.world) {
  %a = idr.call @square(%x) : (i64) -> i64
  %b = idr.call @square(%x) : (i64) -> i64
  %u = idr.call @unused(%x) : (i64) -> i64
  %b1 = idr.call @boxes(%x) : (i64) -> !Box
  %b2 = idr.call @boxes(%x) : (i64) -> !Box
  %u2 = idr.call @boxes(%x) : (i64) -> !Box
  %c1 = idr.call @crashes(%x) : (i64) -> i64
  %c2 = idr.call @crashes(%x) : (i64) -> i64
  %p1 = idr.call @partial(%x) : (i64) -> i64
  %p2 = idr.call @partial(%x) : (i64) -> i64
  %w1 = idr.call @writes(%x, %w) : (i64, !idr.world) -> !idr.world
  %w2 = idr.call @writes(%x, %w1) : (i64, !idr.world) -> !idr.world
  return %a, %b, %b1, %b2, %c1, %c2, %p1, %p2, %w2 : i64, i64, !Box, !Box, i64, i64, i64, i64, !idr.world
}
