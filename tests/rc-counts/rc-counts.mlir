// RUN: idris-mlir-opt %s --idr-rc --idr-expect=holds=reuses-in-place=@map,counts-nothing=@sum,counts-nothing=@scalars -o /dev/null
// RUN: idris-mlir-opt %s --idr-rc -o %t.owned.mlir
// RUN: %differential %s %t.owned.mlir
// idr-rc makes every reference explicit. That each is consumed exactly once
// on every path is the owned stage's rule, which idris-mlir-opt verifies
// after the pass; this test checks what the passes choose.

// A map over a list takes each cell apart where it matches it, the fields
// moving out with no count changed, and builds the new cell in it: it
// reuses in place (the first RUN line). A function that only reads its
// list borrows it (a plain parameter, a view of the caller's), and counts
// nothing; neither do worlds and scalars.

// A string consumed twice is owned, and the first consuming use takes a
// reference of its own from a view of it; one only read is borrowed.

// The input byte sets the list's length, 0 to 7, so map and sum run on
// the empty list and on cells; every run prints what it printed before
// counting and leaves no cell live.
!L = !idr.data<"L", list [@N() nil, @C(i64, !idr.box<!idr.data<"L">>) cons]>
!Two = !idr.data<"Two", plain [@Two(!idr.str, !idr.str)]>
idr.program @counts root(@root) stage(first) {
  idr.func @map(%l: !idr.box<!L>) -> !idr.box<!L> {
    %n = idr.constant !idr.box<!L> #idr.con<!L, @N, []>
    %r = idr.match %l : !idr.box<!L> -> (!idr.box<!L>) {
    case @N() {
      idr.yield %n : !idr.box<!L>
    }
    case @C(%h: i64, %t: !idr.box<!L>) {
      %h2 = arith.muli %h, %h : i64
      %t2 = idr.call @map(%t) : (!idr.box<!L>) -> !idr.box<!L>
      %c = idr.con !idr.box<!L> @C(%h2 : i64, %t2 : !idr.box<!L>)
      idr.yield %c : !idr.box<!L>
    }
    }
    return %r : !idr.box<!L>
  }
  idr.func @sum(%l: !idr.box<!L>, %acc: i64) -> i64 {
    %r = idr.match %l : !idr.box<!L> -> (i64) {
    case @N() {
      idr.yield %acc : i64
    }
    case @C(%h: i64, %t: !idr.box<!L>) {
      %a = arith.addi %acc, %h : i64
      %s = idr.call @sum(%t, %a) : (!idr.box<!L>, i64) -> i64
      idr.yield %s : i64
    }
    }
    return %r : i64
  }
  idr.func @both(%a: !idr.str, %b: !idr.str) -> (!Two, i64) {
    %p = idr.con !Two @Two(%a : !idr.str, %a : !idr.str)
    %n = idr.str.length %b
    return %p, %n : !Two, i64
  }
  idr.func @scalars(%w: !idr.world, %x: i64) -> !idr.world {
    %w2 = idr.io.put_sint %x, %w : i64
    return %w2 : !idr.world
  }
  idr.func @build(%n: i64) -> !idr.box<!L> {
    %r = idr.match_lit %n : i64 -> (!idr.box<!L>) {
    case 0 {
      %e = idr.constant !idr.box<!L> #idr.con<!L, @N, []>
      idr.yield %e : !idr.box<!L>
    }
    default(%d0: i64) {
      %one = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %t = idr.call @build(%m) : (i64) -> !idr.box<!L>
      %c = idr.con !idr.box<!L> @C(%n : i64, %t : !idr.box<!L>)
      idr.yield %c : !idr.box<!L>
    }
    }
    return %r : !idr.box<!L>
  }
  idr.func @root(%w: !idr.world) -> !idr.world {
    %ch, %w0 = idr.io.get_byte %w
    %b = arith.extui %ch : i32 to i64
    %c8 = arith.constant 8 : i64
    %n = arith.remui %b, %c8 : i64
    %c = idr.constant !idr.str "x"
    %p:2 = idr.call @both(%c, %c) : (!idr.str, !idr.str) -> (!Two, i64)
    %l = idr.call @build(%n) : (i64) -> !idr.box<!L>
    %m = idr.call @map(%l) : (!idr.box<!L>) -> !idr.box<!L>
    %z = arith.constant 0 : i64
    %s = idr.call @sum(%m, %z) : (!idr.box<!L>, i64) -> i64
    %w1 = idr.io.put_sint %p#1, %w0 : i64
    %w2 = idr.io.put_sint %s, %w1 : i64
    %w3 = idr.call @scalars(%w2, %s) : (!idr.world, i64) -> !idr.world
    return %w3 : !idr.world
  }
}
