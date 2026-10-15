// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s
// RUN: idris-mlir-opt %s --canonicalize=test-convergence=true -o /dev/null
// NEEDS-ACCEPTANCE: the printed form of the constructor op, C01's.
// An evaluated suspension holds its value: `idr.delay %x`, whose operand is
// the value, with no region. Forcing it computes nothing, so a force of it
// folds to the value, a plain one or a cell built from values above it. A
// suspension that computes is a function of its own, which idr.suspend
// names; forced once and used nowhere else, it is a call of that function.


// CHECK-LABEL: @forced(
// CHECK-SAME: %[[X:[^:]*]]: i64)
// CHECK-NEXT: return %[[X]] : i64
!P = !idr.data<"P", plain [@MkP(i64, i64)]>
idr.func private @forced(%x: i64) -> i64 {
  %t = idr.delay %x : i64 -> !idr.lazy<i64>
  %v = idr.force %t : !idr.lazy<i64> -> i64
  return %v : i64
}

// CHECK-LABEL: @forced_built(
// CHECK-SAME: %[[X:[^:]*]]: i64, %[[Y:[^:]*]]: i64)
// CHECK-NEXT: %[[P:.*]] = {{(idr\.)?}}con
// CHECK-NEXT: return %[[P]]
idr.func private @forced_built(%x: i64, %y: i64) -> !P {
  %p = idr.con @MkP(%x, %y) : (i64, i64) -> !P
  %t = idr.delay %p : !P -> !idr.lazy<!P>
  %v = idr.force %t : !idr.lazy<!P> -> !P
  return %v : !P
}

idr.func private @square(%x: i64) -> i64 attributes {total} {
  %y = arith.muli %x, %x : i64
  return %y : i64
}

// CHECK-LABEL: @computed(
// CHECK-NOT: force
// CHECK: call @square(
idr.func private @computed(%x: i64) -> i64 {
  %t = idr.suspend @square(%x) : (i64) -> !idr.lazy<i64>
  %v = idr.force %t : !idr.lazy<i64> -> i64
  return %v : i64
}
