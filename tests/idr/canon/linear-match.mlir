// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s
// RUN: idris-mlir-opt %s --canonicalize=test-convergence=true -o /dev/null
// A match takes a linear value apart, as its one use. A match on a linear
// parameter stays, one region or many: there is no other reader to read
// its fields from. A match on a value that entered its grade from a
// constructor is that constructor's region, its fields the constructor's,
// held as the region held them; its default region gets the value back.

!P = !idr.data<"P", plain [@MkP(i64, !idr.lin<i64>)]>
!P2 = !idr.data<"P2", plain [@MkP2(!idr.lin<i64>, !idr.lin<i64>)]>
!Q = !idr.data<"Q", plain [@A(i64), @B()]>
idr.func private @keep(%q: !idr.lin<!Q>) -> i64 {
  idr.crash "no body"
  ub.unreachable
}

// CHECK-LABEL: idr.func private @of_param(
// CHECK: match
idr.func private @of_param(%p: !idr.lin<!P>) -> i64 {
  %r = idr.match %p : !idr.lin<!P> -> (i64) {
  case @MkP(%a: i64, %b: !idr.lin<i64>) {
    %x = idr.lin.use %b : !idr.lin<i64>
    %s = arith.addi %a, %x : i64
    idr.yield %s : i64
  }
  }
  return %r : i64
}

// CHECK-LABEL: idr.func private @of_con(
// CHECK-SAME: %[[A:.*]]: i64, %[[B:.*]]: !idr.lin<i64>)
// CHECK-NOT: {{(idr\.| )match }}
// CHECK: %[[X:.*]] = idr.lin.use %[[B]]
// CHECK: arith.addi %[[A]], %[[X]]
idr.func private @of_con(%a: i64, %b: !idr.lin<i64>) -> i64 {
  %c = idr.con @MkP(%a, %b) : (i64, !idr.lin<i64>) -> !P
  %p = idr.lin.enter %c : !idr.lin<!P>
  %r = idr.match %p : !idr.lin<!P> -> (i64) {
  case @MkP(%x: i64, %y: !idr.lin<i64>) {
    %v = idr.lin.use %y : !idr.lin<i64>
    %s = arith.addi %x, %v : i64
    idr.yield %s : i64
  }
  }
  return %r : i64
}

// Two linear fields of one constructor, each read once: both move into
// their reads, and the constructor goes.
// CHECK-LABEL: idr.func private @two_reads(
// CHECK-SAME: %[[A2:[a-z0-9_]+]]: !idr.lin<i64>, %[[B2:[a-z0-9_]+]]: !idr.lin<i64>
// CHECK-NOT: {{(idr\.| )con }}
// CHECK-DAG: %[[X2:.*]] = idr.lin.use %[[A2]]
// CHECK-DAG: %[[Y2:.*]] = idr.lin.use %[[B2]]
// CHECK: arith.addi
// CHECK-LABEL: idr.func @gives_back(
// CHECK: %[[P:.*]] = idr.lin.enter
// CHECK-NOT: {{(idr\.| )match }}
// CHECK: call @keep(%[[P]])
idr.func private @two_reads(%a: !idr.lin<i64>, %b: !idr.lin<i64>) -> i64 {
  %c = idr.con @MkP2(%a, %b) : (!idr.lin<i64>, !idr.lin<i64>) -> !P2
  %x = idr.field %c[@MkP2, 0] : !P2 -> i64
  %y = idr.field %c[@MkP2, 1] : !P2 -> i64
  %s = arith.addi %x, %y : i64
  return %s : i64
}
idr.func @gives_back() -> i64 {
  %c = idr.con @B() : () -> !Q
  %p = idr.lin.enter %c : !idr.lin<!Q>
  %r = idr.match %p : !idr.lin<!Q> -> (i64) {
  case @A(%x: i64) {
    idr.yield %x : i64
  }
  default(%q: !idr.lin<!Q>) {
    %k = idr.call @keep(%q) : (!idr.lin<!Q>) -> i64
    idr.yield %k : i64
  }
  }
  return %r : i64
}
