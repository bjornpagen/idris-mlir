// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr-rc,idr.func(idr-tail-loops)))' | FileCheck %s
// NEEDS-ACCEPTANCE: the input is a program of the first stage, which idr-rc counts first: at the owned stage every reference of ours is graded, so the checks are of the counted program; confirm them against it.
// NEEDS-ACCEPTANCE: syntax swept to the data-type-first form
// What a loop does not change runs once, before it, where it may run
// whatever the loop then does. A loop that decides on a box goes round on
// one constructor, and reads its fields: a read of a box's field is a load
// from its cell, which is as large as its own constructor (an atom is its
// header alone). Before the loop, the read would run when the box is the
// other constructor too, and load past the end of its cell: so it stays in
// the loop, after the test of the tag. A sum's field is one of its slots,
// there whatever the constructor: its read moves out of the loop.
// CHECK-LABEL: idr.func @spin(
// CHECK-NOT: {{(idr\.| )field }}
// CHECK: scf.while
// CHECK: } do {
// CHECK: field %{{.*}} : !idr.box<!T> @Big[2] -> i64
// CHECK-LABEL: idr.func @spinPair(
// CHECK: field %{{.*}} : !P @MkP[1] -> i64
// CHECK: scf.while
!T = !idr.data<"T", plain [@Small(), @Big(i64, i64, i64, !idr.box<!idr.data<"T">>)]>
!P = !idr.data<"P", plain [@NoP(), @MkP(i64, i64)]>
idr.program @"invariant-fields" root(@root) stage(first) {
  // Ends at once on Small; on a Big it goes round for ever, adding its
  // third field, which does not change from one round to the next.
  idr.func @spin(%t: !idr.box<!T>, %acc: i64) -> i64 {
    %r = idr.match %t : !idr.box<!T> -> (i64) {
    case @Small() {
      idr.yield %acc : i64
    }
    case @Big(%a: i64, %b: i64, %c: i64, %rest: !idr.box<!T>) {
      %s = arith.addi %acc, %c : i64
      %n = idr.call @spin(%t, %s) : (!idr.box<!T>, i64) -> i64
      idr.yield %n : i64
    }
    }
    return %r : i64
  }
  // The same on a sum.
  idr.func @spinPair(%p: !P, %acc: i64) -> i64 {
    %r = idr.match %p : !P -> (i64) {
    case @NoP() {
      idr.yield %acc : i64
    }
    case @MkP(%x: i64, %y: i64) {
      %s = arith.addi %acc, %y : i64
      %n = idr.call @spinPair(%p, %s) : (!P, i64) -> i64
      idr.yield %n : i64
    }
    }
    return %r : i64
  }
  idr.func @root(%w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %small = idr.constant #idr.con<!T, @Small, []> : !idr.box<!T>
    %s = idr.call @spin(%small, %z) : (!idr.box<!T>, i64) -> i64
    %nop = idr.constant #idr.con<!P, @NoP, []> : !P
    %q = idr.call @spinPair(%nop, %z) : (!P, i64) -> i64
    %sq = arith.addi %s, %q : i64
    %w1 = idr.io.put_int signed %sq, %w : i64
    return %w1 : !idr.world
  }
}
