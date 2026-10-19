// RUN: idris-mlir-opt %s --idr-rc --idr-expect=holds=no-heap-allocation=@local -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-rc --idr-expect=holds=reuses-in-place=@rebuilt -o /dev/null 2> %t.err
// RUN: FileCheck %s --check-prefix=FRESH < %t.err
// The cell of %p dies in the function that makes it, so idr-rc's stack
// step makes it in the frame, before reuse and exclusivity read where each
// cell comes from: a cell in a frame is never exclusive (the frame holds
// it), and never recycled, here for the list @rebuilt returns, which is a
// cell of the heap of its own: reuses-in-place fails of @rebuilt.
// FRESH: error: expected reuses-in-place: {{.*}} in @rebuilt
!L = !idr.data<"L", list [@N() nil, @C(i64, !idr.box<!idr.data<"L">>) cons]>
idr.program @stackcell root(@root) stage(first) {
  idr.func @local(%x: i64, %t: !idr.box<!L>) -> i64 {
    %p = idr.con !idr.box<!L> @C(%x : i64, %t : !idr.box<!L>)
    %r = idr.match %p : !idr.box<!L> -> (i64) {
    case @N() {
      %z = arith.constant 0 : i64
      idr.yield %z : i64
    }
    case @C(%h: i64, %u: !idr.box<!L>) {
      %one = arith.constant 1 : i64
      %h2 = arith.addi %h, %one : i64
      idr.yield %h2 : i64
    }
    }
    return %r : i64
  }
  idr.func @rebuilt(%x: i64, %t: !idr.box<!L>) -> !idr.box<!L> {
    %p = idr.con !idr.box<!L> @C(%x : i64, %t : !idr.box<!L>)
    %r = idr.match %p : !idr.box<!L> -> (!idr.box<!L>) {
    case @N() {
      %n = idr.constant !idr.box<!L> #idr.con<!L, @N, []>
      idr.yield %n : !idr.box<!L>
    }
    case @C(%h: i64, %u: !idr.box<!L>) {
      %one = arith.constant 1 : i64
      %h2 = arith.addi %h, %one : i64
      %c = idr.con !idr.box<!L> @C(%h2 : i64, %u : !idr.box<!L>)
      idr.yield %c : !idr.box<!L>
    }
    }
    return %r : !idr.box<!L>
  }
  idr.func @root() -> i64 {
    %x = arith.constant 7 : i64
    %n = idr.constant !idr.box<!L> #idr.con<!L, @N, []>
    %a = idr.call @local(%x, %n) : (i64, !idr.box<!L>) -> i64
    %l = idr.call @rebuilt(%x, %n) : (i64, !idr.box<!L>) -> !idr.box<!L>
    %h = idr.match %l : !idr.box<!L> -> (i64) {
    case @N() {
      idr.yield %a : i64
    }
    case @C(%y: i64, %u: !idr.box<!L>) {
      %s = arith.addi %a, %y : i64
      idr.yield %s : i64
    }
    }
    return %h : i64
  }
}
