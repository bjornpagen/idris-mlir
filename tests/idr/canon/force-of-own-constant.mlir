// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s
// RUN: idris-mlir-opt %s --canonicalize=test-convergence=true -o /dev/null
// A constant suspension is one cell in static data, whose force runs its
// label once. Every force of it stays a force: a call of the label in its
// place would run the label again at each force, and in a knot (the
// label's own constant, or one a function it calls holds) would recurse
// where the cell's running state ends the program. So canonicalize leaves
// every force of a constant, whatever the label reaches.
// CHECK-LABEL: @knot(
// CHECK: force
// CHECK-NOT: call @knot
// CHECK: return
// CHECK-LABEL: @mid(
// CHECK: force
// CHECK-NOT: call @label
// CHECK: return
// CHECK-LABEL: @other(
// CHECK: force
// CHECK-NOT: call @leaf
// CHECK: return

// The label forces its own constant.
idr.func private @knot() -> i64 {
  %c = idr.constant #idr.closure<@knot, []> : !idr.lazy<i64>
  %v = idr.force %c : !idr.lazy<i64> -> i64
  %one = arith.constant 1 : i64
  %r = arith.addi %v, %one : i64
  return %r : i64
}

// The label calls the function that forces its constant.
idr.func private @label() -> i64 {
  %r = idr.call @mid() : () -> i64
  return %r : i64
}
idr.func private @mid() -> i64 {
  %c = idr.constant #idr.closure<@label, []> : !idr.lazy<i64>
  %v = idr.force %c : !idr.lazy<i64> -> i64
  return %v : i64
}

// The label reaches nothing that holds its constant.
idr.func private @leaf() -> i64 attributes {total} {
  %c = arith.constant 7 : i64
  return %c : i64
}
idr.func private @other() -> i64 {
  %c = idr.constant #idr.closure<@leaf, []> : !idr.lazy<i64>
  %v = idr.force %c : !idr.lazy<i64> -> i64
  return %v : i64
}
