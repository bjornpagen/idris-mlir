// RUN: idris-mlir-opt %s --idr-rc --idr-expect=holds=reuses-every-cell=@f -o /dev/null
// RUN: idris-mlir-opt %s --idr-rc | FileCheck %s
// NEEDS-ACCEPTANCE: idr-rc classifies values on the code each step sees (classes built per step): a field whose box's take moved its later uses may now be a view, one dup and drop fewer.
// A box read only through its fields, never matched, dies where its last
// field is read, and is taken apart there as a matched one is: its cell is
// one more to build in. `f` matches the outer cell, reads the inner one's
// two numbers by idr.field and rebuilds both, the inner one swapped: each
// of the two constructors it builds goes into one of the two cells that
// died, and neither cell is freed (reuses-every-cell).
// CHECK-LABEL: idr.func @f(
// CHECK-DAG: take %{{.*}} : {{.*}}@MkP
// CHECK-DAG: take %{{.*}} : {{.*}}@MkQ
// CHECK-DAG: reuse %{{.*}} @MkQ(
// CHECK-DAG: reuse %{{.*}} @MkP(
// CHECK-LABEL: idr.func @root(
!Q = !idr.data<"Q", plain [@MkQ(i64, i64)]>
!P = !idr.data<"P", plain [@MkP(i64, !idr.box<!Q>)]>
idr.program @"nested-reuse" root(@root) stage(first) {
  idr.func @f(%p: !idr.box<!P>) -> !idr.box<!P> {
    %r = idr.match %p : !idr.box<!P> -> (!idr.box<!P>) {
    case @MkP(%x: i64, %q: !idr.box<!Q>) {
      %a = idr.field %q : !idr.box<!Q> @MkQ[0] -> i64
      %b = idr.field %q : !idr.box<!Q> @MkQ[1] -> i64
      %q2 = idr.con !idr.box<!Q> @MkQ(%b : i64, %a : i64)
      %one = arith.constant 1 : i64
      %x2 = arith.addi %x, %one : i64
      %p2 = idr.con !idr.box<!P> @MkP(%x2 : i64, %q2 : !idr.box<!Q>)
      idr.yield %p2 : !idr.box<!P>
    }
    }
    return %r : !idr.box<!P>
  }
  idr.func @root(%w: !idr.world) -> !idr.world {
    %c1 = arith.constant 1 : i64
    %c2 = arith.constant 2 : i64
    %q = idr.con !idr.box<!Q> @MkQ(%c1 : i64, %c2 : i64)
    %p = idr.con !idr.box<!P> @MkP(%c1 : i64, %q : !idr.box<!Q>)
    %p2 = idr.call @f(%p) : (!idr.box<!P>) -> !idr.box<!P>
    %s = idr.match %p2 : !idr.box<!P> -> (i64) {
    case @MkP(%x: i64, %q2: !idr.box<!Q>) {
      %a = idr.field %q2 : !idr.box<!Q> @MkQ[0] -> i64
      %t = arith.addi %x, %a : i64
      idr.yield %t : i64
    }
    }
    %w2 = idr.io.put_int signed %s, %w : i64
    return %w2 : !idr.world
  }
}
