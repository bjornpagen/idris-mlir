// RUN: idris-mlir-opt %s --idr-effects --cse --canonicalize | FileCheck %s
// func.call answers MemoryEffectOpInterface from its callee's facts, so the
// upstream passes treat a call as they treat any op: cse merges two calls of
// a pure total function on the same arguments, canonicalize erases a call
// whose results are unused when it only computes, and a call of a function
// that may crash, perform IO or not return stays, each time it is made. A
// result that is not a scalar is a fresh value the call allocates: two
// such calls stay apart (each makes its own cell) and an unused one goes.
// CHECK-LABEL: func.func @main(
// CHECK: %[[S:.*]] = call @square(%arg0)
// CHECK-NOT: call @square
// CHECK-NOT: call @unused
// CHECK: %[[B1:.*]] = call @boxes(%arg0)
// CHECK: %[[B2:.*]] = call @boxes(%arg0)
// CHECK: %[[C1:.*]] = call @crashes(%arg0)
// CHECK: %[[C2:.*]] = call @crashes(%arg0)
// CHECK: %[[P1:.*]] = call @partial(%arg0)
// CHECK: %[[P2:.*]] = call @partial(%arg0)
// CHECK: %[[W1:.*]] = call @writes(%arg0, %arg1)
// CHECK: %[[W2:.*]] = call @writes(%arg0, %[[W1]])
// CHECK: return %[[S]], %[[S]], %[[B1]], %[[B2]], %[[C1]], %[[C2]], %[[P1]], %[[P2]], %[[W2]]
idr.data @Box {
  idr.ctor @MkBox (i64)
}
func.func private @square(%x: i64) -> i64 attributes {idr.total} {
  %r = arith.muli %x, %x : i64
  return %r : i64
}
func.func private @unused(%x: i64) -> i64 attributes {idr.total} {
  %r = arith.addi %x, %x : i64
  return %r : i64
}
func.func private @boxes(%x: i64) -> !idr.data<@Box> attributes {idr.total} {
  %b = idr.con @Box::@MkBox(%x) : (i64) -> !idr.data<@Box>
  return %b : !idr.data<@Box>
}
func.func private @crashes(%x: i64) -> i64 attributes {idr.total} {
  %y = idr.check.nonzero %x, "division by zero" : i64
  %r = idr.div signed %x, %y : i64
  return %r : i64
}
func.func private @partial(%x: i64) -> i64 {
  %r = arith.muli %x, %x : i64
  return %r : i64
}
func.func private @writes(%x: i64, %w: !idr.world) -> !idr.world attributes {idr.total} {
  %c = arith.constant 65 : i32
  %w1 = idr.io.put_char %c, %w
  return %w1 : !idr.world
}
func.func @main(%x: i64, %w: !idr.world) -> (i64, i64, !idr.data<@Box>, !idr.data<@Box>, i64, i64, i64, i64, !idr.world) {
  %a = func.call @square(%x) : (i64) -> i64
  %b = func.call @square(%x) : (i64) -> i64
  %u = func.call @unused(%x) : (i64) -> i64
  %b1 = func.call @boxes(%x) : (i64) -> !idr.data<@Box>
  %b2 = func.call @boxes(%x) : (i64) -> !idr.data<@Box>
  %u2 = func.call @boxes(%x) : (i64) -> !idr.data<@Box>
  %c1 = func.call @crashes(%x) : (i64) -> i64
  %c2 = func.call @crashes(%x) : (i64) -> i64
  %p1 = func.call @partial(%x) : (i64) -> i64
  %p2 = func.call @partial(%x) : (i64) -> i64
  %w1 = func.call @writes(%x, %w) : (i64, !idr.world) -> !idr.world
  %w2 = func.call @writes(%x, %w1) : (i64, !idr.world) -> !idr.world
  return %a, %b, %b1, %b2, %c1, %c2, %p1, %p2, %w2 : i64, i64, !idr.data<@Box>, !idr.data<@Box>, i64, i64, i64, i64, !idr.world
}
