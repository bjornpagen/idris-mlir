// RUN: idris-mlir-opt %s --idr-rc --idr-expect=holds=reuses-every-cell=@f -o /dev/null
// RUN: idris-mlir-opt %s --idr-rc | FileCheck %s
// A box read only through its fields, never matched, dies where its last
// field is read, and is taken apart there as a matched one is: its cell is
// one more to build in. `f` matches the outer cell, reads the inner one's
// two numbers by idr.field and rebuilds both, the inner one swapped: each
// of the two constructors it builds goes into one of the two cells that
// died, and neither cell is freed (reuses-every-cell).
// CHECK-LABEL: idr.func private @f(
// CHECK-DAG: take %{{.*}} @MkP
// CHECK-DAG: take %{{.*}} @MkQ
// CHECK-DAG: reuse %{{.*}} @MkQ(
// CHECK-DAG: reuse %{{.*}} @MkP(
// CHECK-LABEL: idr.func @root(
!Q = !idr.data<"Q", plain [@MkQ(i64, i64)]>
!P = !idr.data<"P", plain [@MkP(i64, !idr.box<!Q>)]>
module {
  idr.func private @f(%p: !idr.box<!P>) -> !idr.box<!P> {
    %r = idr.match %p : !idr.box<!P> -> (!idr.box<!P>) {
    case @MkP(%x: i64, %q: !idr.box<!Q>) {
      %a = idr.field %q[@MkQ, 0] : !idr.box<!Q> -> i64
      %b = idr.field %q[@MkQ, 1] : !idr.box<!Q> -> i64
      %q2 = idr.con @MkQ(%b, %a) : (i64, i64) -> !idr.box<!Q>
      %one = arith.constant 1 : i64
      %x2 = arith.addi %x, %one : i64
      %p2 = idr.con @MkP(%x2, %q2) : (i64, !idr.box<!Q>) -> !idr.box<!P>
      idr.yield %p2 : !idr.box<!P>
    }
    }
    return %r : !idr.box<!P>
  }
  idr.func @root(%w: !idr.world) -> !idr.world {
    %c1 = arith.constant 1 : i64
    %c2 = arith.constant 2 : i64
    %q = idr.con @MkQ(%c1, %c2) : (i64, i64) -> !idr.box<!Q>
    %p = idr.con @MkP(%c1, %q) : (i64, !idr.box<!Q>) -> !idr.box<!P>
    %p2 = idr.call @f(%p) : (!idr.box<!P>) -> !idr.box<!P>
    %s = idr.match %p2 : !idr.box<!P> -> (i64) {
    case @MkP(%x: i64, %q2: !idr.box<!Q>) {
      %a = idr.field %q2[@MkQ, 0] : !idr.box<!Q> -> i64
      %t = arith.addi %x, %a : i64
      idr.yield %t : i64
    }
    }
    %w2 = idr.io.put_int signed %s, %w : i64
    return %w2 : !idr.world
  }
}
