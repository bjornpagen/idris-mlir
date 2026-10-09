// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s
// A constant suspension is one cell in static data, whose force runs its
// label once. A force of it that nothing else uses becomes a call of the
// label, unless the function holding the force may run while the label
// does: in a knot, the label's own constant, or one a function it calls
// holds, the call would recurse where the cell's running state ends the
// program. That force stays. A label that reaches nothing holding its
// constant is called.
// CHECK-LABEL: func.func private @knot(
// CHECK: idr.force
// CHECK-NOT: call @knot
// CHECK: return
// CHECK-LABEL: func.func private @mid(
// CHECK: idr.force
// CHECK-NOT: call @label
// CHECK: return
// CHECK-LABEL: func.func private @other(
// CHECK-NOT: idr.force
// CHECK: call @leaf()
// CHECK-NOT: idr.force
// CHECK: return

// The label forces its own constant.
func.func private @knot() -> i64 {
  %c = idr.constant #idr.closure<@knot, []> : !idr.lazy<i64>
  %v = idr.force %c : !idr.lazy<i64> -> i64
  %one = arith.constant 1 : i64
  %r = arith.addi %v, %one : i64
  return %r : i64
}

// The label calls the function that forces its constant.
func.func private @label() -> i64 {
  %r = func.call @mid() : () -> i64
  return %r : i64
}
func.func private @mid() -> i64 {
  %c = idr.constant #idr.closure<@label, []> : !idr.lazy<i64>
  %v = idr.force %c : !idr.lazy<i64> -> i64
  return %v : i64
}

// The label reaches nothing that holds its constant.
func.func private @leaf() -> i64 attributes {idr.total} {
  %c = arith.constant 7 : i64
  return %c : i64
}
func.func private @other() -> i64 {
  %c = idr.constant #idr.closure<@leaf, []> : !idr.lazy<i64>
  %v = idr.force %c : !idr.lazy<i64> -> i64
  return %v : i64
}

func.func @main() -> (i64, i64, i64) {
  %a = func.call @knot() : () -> i64
  %b = func.call @label() : () -> i64
  %c = func.call @other() : () -> i64
  return %a, %b, %c : i64, i64, i64
}
