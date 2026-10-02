// RUN: idris-mlir-opt %s --idr-tail-loops | FileCheck %s
// What a loop does not change runs once, before it, where it may run
// whatever the loop then does. A loop that decides on a box goes round on
// one constructor, and reads its fields: a read of a box's field is a load
// from its cell, which is as large as its own constructor (an atom is its
// header alone). Before the loop, the read would run when the box is the
// other constructor too, and load past the end of its cell: so it stays in
// the loop, after the test of the tag. A sum's field is one of its slots,
// there whatever the constructor: its read moves out of the loop.
// CHECK-LABEL: func.func private @spin(
// CHECK-NOT: idr.field
// CHECK: scf.while
// CHECK: } do {
// CHECK: idr.field %{{.*}}[@Big, 2] : !idr.box<@T> -> i64
// CHECK-LABEL: func.func private @spinPair(
// CHECK: idr.field %{{.*}}[@MkP, 1] : !idr.data<@P> -> i64
// CHECK: scf.while
module attributes {idr.program} {
  idr.data @T box {
    idr.ctor @Small ()
    idr.ctor @Big (i64, i64, i64, !idr.box<@T>)
  }
  idr.data @P {
    idr.ctor @NoP ()
    idr.ctor @MkP (i64, i64)
  }
  // Ends at once on Small; on a Big it goes round for ever, adding its
  // third field, which does not change from one round to the next.
  func.func private @spin(%t: !idr.box<@T>, %acc: i64) -> i64 {
    %r = idr.match %t : !idr.box<@T> -> (i64) {
    case @Small() {
      idr.yield %acc : i64
    }
    case @Big(%a: i64, %b: i64, %c: i64, %rest: !idr.box<@T>) {
      %s = arith.addi %acc, %c : i64
      %n = func.call @spin(%t, %s) : (!idr.box<@T>, i64) -> i64
      idr.yield %n : i64
    }
    }
    return %r : i64
  }
  // The same on a sum.
  func.func private @spinPair(%p: !idr.data<@P>, %acc: i64) -> i64 {
    %r = idr.match %p : !idr.data<@P> -> (i64) {
    case @NoP() {
      idr.yield %acc : i64
    }
    case @MkP(%x: i64, %y: i64) {
      %s = arith.addi %acc, %y : i64
      %n = func.call @spinPair(%p, %s) : (!idr.data<@P>, i64) -> i64
      idr.yield %n : i64
    }
    }
    return %r : i64
  }
  func.func @root(%w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %small = idr.constant #idr.con<@T::@Small, []> : !idr.box<@T>
    %s = func.call @spin(%small, %z) : (!idr.box<@T>, i64) -> i64
    %nop = idr.constant #idr.con<@P::@NoP, []> : !idr.data<@P>
    %q = func.call @spinPair(%nop, %z) : (!idr.data<@P>, i64) -> i64
    %sq = arith.addi %s, %q : i64
    %w1 = idr.io.put_int signed %sq, %w : i64
    return %w1 : !idr.world
  }
}
