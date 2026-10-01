// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s
// A match takes a linear value apart, as its one use. A match on a linear
// parameter stays, one region or many: there is no other reader to read
// its fields from. A match on a value that entered its grade from a
// constructor is that constructor's region, its fields the constructor's,
// held as the region held them; its default region gets the value back.

idr.data @P {
  idr.ctor @MkP (i64, !idr.lin<i64>)
}
idr.data @P2 {
  idr.ctor @MkP2 (!idr.lin<i64>, !idr.lin<i64>)
}
idr.data @Q {
  idr.ctor @A (i64)
  idr.ctor @B ()
}
func.func private @keep(%q: !idr.lin<!idr.data<@Q>>) -> i64

// CHECK-LABEL: func.func @of_param(
// CHECK: idr.match
func.func @of_param(%p: !idr.lin<!idr.data<@P>>) -> i64 {
  %r = idr.match %p : !idr.lin<!idr.data<@P>> -> (i64) {
  case @MkP(%a: i64, %b: !idr.lin<i64>) {
    %x = idr.lin.use %b : !idr.lin<i64>
    %s = arith.addi %a, %x : i64
    idr.yield %s : i64
  }
  }
  return %r : i64
}

// CHECK-LABEL: func.func @of_con(
// CHECK-SAME: %[[A:.*]]: i64, %[[B:.*]]: !idr.lin<i64>)
// CHECK-NOT: idr.match
// CHECK: %[[X:.*]] = idr.lin.use %[[B]]
// CHECK: arith.addi %[[A]], %[[X]]
func.func @of_con(%a: i64, %b: !idr.lin<i64>) -> i64 {
  %c = idr.con @P::@MkP(%a, %b) : (i64, !idr.lin<i64>) -> !idr.data<@P>
  %p = idr.lin.enter %c : !idr.lin<!idr.data<@P>>
  %r = idr.match %p : !idr.lin<!idr.data<@P>> -> (i64) {
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
// CHECK-LABEL: func.func @two_reads(
// CHECK-SAME: %[[A2:[a-z0-9_]+]]: !idr.lin<i64>, %[[B2:[a-z0-9_]+]]: !idr.lin<i64>
// CHECK-NOT: idr.con
// CHECK-DAG: %[[X2:.*]] = idr.lin.use %[[A2]]
// CHECK-DAG: %[[Y2:.*]] = idr.lin.use %[[B2]]
// CHECK: arith.addi
// CHECK-LABEL: func.func @gives_back(
// CHECK: %[[P:.*]] = idr.lin.enter
// CHECK-NOT: idr.match
// CHECK: call @keep(%[[P]])
func.func @two_reads(%a: !idr.lin<i64>, %b: !idr.lin<i64>) -> i64 {
  %c = idr.con @P2::@MkP2(%a, %b) : (!idr.lin<i64>, !idr.lin<i64>) -> !idr.data<@P2>
  %x = idr.field %c[@MkP2, 0] : !idr.data<@P2> -> i64
  %y = idr.field %c[@MkP2, 1] : !idr.data<@P2> -> i64
  %s = arith.addi %x, %y : i64
  return %s : i64
}
func.func @gives_back() -> i64 {
  %c = idr.con @Q::@B() : () -> !idr.data<@Q>
  %p = idr.lin.enter %c : !idr.lin<!idr.data<@Q>>
  %r = idr.match %p : !idr.lin<!idr.data<@Q>> -> (i64) {
  case @A(%x: i64) {
    idr.yield %x : i64
  }
  default(%q: !idr.lin<!idr.data<@Q>>) {
    %k = func.call @keep(%q) : (!idr.lin<!idr.data<@Q>>) -> i64
    idr.yield %k : i64
  }
  }
  return %r : i64
}
