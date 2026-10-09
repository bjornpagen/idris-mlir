// RUN: idris-mlir-opt %s --idr-lower | FileCheck %s
// S has three constructors, so an i8 tag; B's i32 and C's flattened P
// (i64, i8) get separate slots; the erased field has none. The match reads
// each case's fields in its region; with no default, the last case is the
// default (Idris proved the others impossible).
// CHECK-NOT: idr.
// CHECK-LABEL: func.func private @f(
// CHECK-SAME: %[[TAG:[^:]*]]: i8{{( \{[^}]*\})?}}, %[[B0:[^:]*]]: i32, %[[P0:.*]]: i64, %[[P1:.*]]: i8) -> i64
// CHECK: %[[T:.*]] = arith.extui %[[TAG]] : i8 to i64
// CHECK: %[[I:.*]] = arith.index_cast %[[T]] : i64 to index
// CHECK: scf.index_switch %[[I]] -> i64
// CHECK: case 0 {
// CHECK: case 1 {
// CHECK: arith.extsi %[[B0]]
// CHECK: default {
// CHECK: scf.yield %[[P0]] : i64
// CHECK-LABEL: func.func @Prog.main() -> i64
// CHECK-DAG: %[[FIVE:.*]] = arith.constant 5 : i32
// CHECK-DAG: %[[ONE:.*]] = arith.constant 1 : i8
// CHECK-DAG: %[[U1:.*]] = llvm.mlir.zero : i64
// CHECK-DAG: %[[U2:.*]] = llvm.mlir.zero : i8
// CHECK: call @f(%[[ONE]], %[[FIVE]], %[[U1]], %[[U2]])
module attributes {idr.program} {
  idr.data @P {
    idr.ctor @MkP (i64, i8)
  }
  idr.data @S {
    idr.ctor @A ()
    idr.ctor @B (i32, !idr.erased)
    idr.ctor @C (!idr.data<@P>)
  }
  func.func private @f(%s: !idr.data<@S>) -> i64 {
    %r = idr.match %s : !idr.data<@S> -> (i64) {
    case @A() {
      %z = arith.constant 0 : i64
      idr.yield %z : i64
    }
    case @B(%x: i32, %e: !idr.erased) {
      %y = arith.extsi %x : i32 to i64
      idr.yield %y : i64
    }
    case @C(%p: !idr.data<@P>) {
      %z = idr.field %p[@MkP, 0] : !idr.data<@P> -> i64
      idr.yield %z : i64
    }
    }
    return %r : i64
  }
  func.func @Prog.main() -> i64 {
    %e = idr.constant #idr.erased : !idr.erased
    %c5 = arith.constant 5 : i32
    %s = idr.con @S::@B(%c5, %e) : (i32, !idr.erased) -> !idr.data<@S>
    %r = func.call @f(%s) : (!idr.data<@S>) -> i64
    return %r : i64
  }
}
