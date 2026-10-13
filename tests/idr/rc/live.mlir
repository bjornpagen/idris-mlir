// RUN: idris-mlir -c %s -o %t.o
// RUN: %cc %t.o -o %t
// RUN: %status 149 env IDRIS_RT_LIVE=1 %t 2> %t.err
// RUN: grep -qx 'idris-rt: live cells 0' %t.err
// Every cell a program allocates is freed by the time it ends, whichever
// way the counting went: a list mapped in place, a list read and then
// consumed, a shared list mapped into fresh cells while it is still read
// afterwards, and lists of which only the head is used.
module attributes {idr.program} {
  idr.data @L box {
    idr.ctor @N ()
    idr.ctor @C (i64, !idr.box<@L>)
  }
  idr.func private @build(%n: i64) -> !idr.box<@L> {
    %r = idr.match_lit %n : i64 -> (!idr.box<@L>) {
    case 0 {
      %e = idr.constant #idr.con<@L::@N, []> : !idr.box<@L>
      idr.yield %e : !idr.box<@L>
    }
    default {
      %one = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %t = idr.call @build(%m) : (i64) -> !idr.box<@L>
      %c = idr.con @L::@C(%n, %t) : (i64, !idr.box<@L>) -> !idr.box<@L>
      idr.yield %c : !idr.box<@L>
    }
    }
    return %r : !idr.box<@L>
  }
  idr.func private @map(%l: !idr.box<@L>) -> !idr.box<@L> {
    %r = idr.match %l : !idr.box<@L> -> (!idr.box<@L>) {
    case @N() {
      %e = idr.constant #idr.con<@L::@N, []> : !idr.box<@L>
      idr.yield %e : !idr.box<@L>
    }
    case @C(%h: i64, %t: !idr.box<@L>) {
      %h2 = arith.muli %h, %h : i64
      %t2 = idr.call @map(%t) : (!idr.box<@L>) -> !idr.box<@L>
      %c = idr.con @L::@C(%h2, %t2) : (i64, !idr.box<@L>) -> !idr.box<@L>
      idr.yield %c : !idr.box<@L>
    }
    }
    return %r : !idr.box<@L>
  }
  idr.func private @sum(%l: !idr.box<@L>, %acc: i64) -> i64 {
    %r = idr.match %l : !idr.box<@L> -> (i64) {
    case @N() {
      idr.yield %acc : i64
    }
    case @C(%h: i64, %t: !idr.box<@L>) {
      %a = arith.addi %acc, %h : i64
      %s = idr.call @sum(%t, %a) : (!idr.box<@L>, i64) -> i64
      idr.yield %s : i64
    }
    }
    return %r : i64
  }
  idr.func private @head(%l: !idr.box<@L>) -> i64 {
    %r = idr.match %l : !idr.box<@L> -> (i64) {
    case @N() {
      %z = arith.constant 0 : i64
      idr.yield %z : i64
    }
    case @C(%h: i64, %t: !idr.box<@L>) {
      idr.yield %h : i64
    }
    }
    return %r : i64
  }
  idr.func @Prog.main() -> i64 {
    %zero = arith.constant 0 : i64
    %ten = arith.constant 10 : i64
    %three = arith.constant 3 : i64
    %l = idr.call @build(%ten) : (i64) -> !idr.box<@L>
    %m = idr.call @map(%l) : (!idr.box<@L>) -> !idr.box<@L>
    %s1 = idr.call @sum(%m, %zero) : (!idr.box<@L>, i64) -> i64
    %m2 = idr.call @map(%m) : (!idr.box<@L>) -> !idr.box<@L>
    %s2 = idr.call @sum(%m2, %zero) : (!idr.box<@L>, i64) -> i64
    %h = idr.call @head(%m2) : (!idr.box<@L>) -> i64
    %k = idr.call @build(%three) : (i64) -> !idr.box<@L>
    %a = idr.call @map(%k) : (!idr.box<@L>) -> !idr.box<@L>
    %b = idr.call @sum(%k, %zero) : (!idr.box<@L>, i64) -> i64
    %ha = idr.call @head(%a) : (!idr.box<@L>) -> i64
    %t1 = arith.addi %s1, %s2 : i64
    %t2 = arith.addi %t1, %h : i64
    %t3 = arith.addi %t2, %b : i64
    %t4 = arith.addi %t3, %ha : i64
    %c256 = arith.constant 256 : i64
    %r = arith.remsi %t4, %c256 : i64
    return %r : i64
  }
}
