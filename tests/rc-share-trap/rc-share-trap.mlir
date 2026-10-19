// RUN: %status 1 idris-mlir-opt %s --idr-rc --idr-expect=holds=tests-nothing=@bump -o /dev/null 2> %t.err
// RUN: FileCheck %s < %t.err
// @root builds a fresh list, then gives it to @bump while it still reads
// it in @sum: the list is shared where @bump consumes it, an idr.share of
// a value that was exclusive. A share gives the same cell up as one of
// several references, so nothing past it holds the only one, and @bump,
// which gets its list only that way, tests every cell's count.
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
  idr.func @root() -> i64 {
    %c3 = arith.constant 3 : i64
    %z = arith.constant 0 : i64
    %l = idr.call @build(%c3) : (i64) -> !idr.box<!L>
    %b = idr.call @bump(%l) : (!idr.box<!L>) -> !idr.box<!L>
    %s = idr.call @sum(%l, %z) : (!idr.box<!L>, i64) -> i64
    %t = idr.call @sum(%b, %s) : (!idr.box<!L>, i64) -> i64
    return %t : i64
  }
}
