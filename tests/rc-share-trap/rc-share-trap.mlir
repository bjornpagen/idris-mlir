// RUN: %status 1 idris-mlir-opt %s --idr-rc --idr-expect=holds=tests-nothing=@bump -o /dev/null 2> %t.err
// RUN: FileCheck %s < %t.err
// RUN: idris-mlir-opt %s --idr-rc -o %t.owned.mlir
// RUN: %differential %s %t.owned.mlir
// @root builds a fresh list, then gives it to @bump while it still reads
// it in @sum: the list is shared where @bump consumes it, an idr.share of
// a value that was exclusive. A share gives the same cell up as one of
// several references, so nothing past it holds the only one, and @bump,
// which gets its list only that way, tests every cell's count. The input
// byte sets the list's length, 0 to 5, so the shared list's every cell is
// tested, the empty list too, and every run prints what it printed before
// counting and leaves no cell live: the cells @bump copies and the ones
// @sum reads after it.
// CHECK: error: expected tests-nothing: idr.take in @bump tests
!L = !idr.data<"L", list [@N() nil, @C(i64, !idr.box<!idr.data<"L">>) cons]>
idr.program @sharetrap root(@root) stage(first) {
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
  idr.func @bump(%l: !idr.box<!L>) -> !idr.box<!L> {
    %n = idr.constant !idr.box<!L> #idr.con<!L, @N, []>
    %r = idr.match %l : !idr.box<!L> -> (!idr.box<!L>) {
    case @N() {
      idr.yield %n : !idr.box<!L>
    }
    case @C(%h: i64, %t: !idr.box<!L>) {
      %one = arith.constant 1 : i64
      %h2 = arith.addi %h, %one : i64
      %t2 = idr.call @bump(%t) : (!idr.box<!L>) -> !idr.box<!L>
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
  idr.func @root(%w: !idr.world) -> !idr.world {
    %ch, %w0 = idr.io.get_byte %w
    %byte = arith.extui %ch : i32 to i64
    %c6 = arith.constant 6 : i64
    %c3 = arith.remui %byte, %c6 : i64
    %z = arith.constant 0 : i64
    %l = idr.call @build(%c3) : (i64) -> !idr.box<!L>
    %b = idr.call @bump(%l) : (!idr.box<!L>) -> !idr.box<!L>
    %s = idr.call @sum(%l, %z) : (!idr.box<!L>, i64) -> i64
    %k = arith.constant 1000 : i64
    %sk = arith.muli %s, %k : i64
    %t = idr.call @sum(%b, %sk) : (!idr.box<!L>, i64) -> i64
    %w1 = idr.io.put_sint %t, %w0 : i64
    return %w1 : !idr.world
  }
}
