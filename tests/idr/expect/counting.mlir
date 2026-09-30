// RUN: idris-mlir-opt %s --idr-rc --idr-expect=holds=reuses-in-place=@map,counts-nothing=@sum -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-rc=reuse=false --idr-expect=holds=reuses-in-place=@map -o /dev/null 2> %t.fresh.err
// RUN: FileCheck %s --check-prefix=FRESH < %t.fresh.err
// RUN: %status 1 idris-mlir-opt %s --idr-rc --idr-expect=holds=counts-nothing=@both,reuses-in-place=@both -o /dev/null 2> %t.both.err
// RUN: FileCheck %s --check-prefix=BOTH < %t.both.err
// What reference counting leaves in a function, as properties. A map over
// a list builds each cell in the one it took apart, and a sum that only
// reads its list counts nothing. Without reuse the map's cells are
// fresh; a function that keeps a string twice counts, and reuses nothing.
// FRESH: error: expected reuses-in-place: a box of @L::@C gets a fresh cell in @map
// FRESH: error: expected reuses-in-place: nothing is built in a reused cell in @map
// BOTH-DAG: error: expected counts-nothing: idr.dup in @both
// BOTH-DAG: error: expected reuses-in-place: nothing is built in a reused cell in @both
module attributes {idr.program} {
  idr.data @L box {
    idr.ctor @N ()
    idr.ctor @C (i64, !idr.box<@L>)
  }
  idr.data @Two {
    idr.ctor @Two (!idr.str, !idr.str)
  }
  func.func private @map(%l: !idr.box<@L>) -> !idr.box<@L> {
    %n = idr.constant #idr.con<@L::@N, []> : !idr.box<@L>
    %r = idr.match %l : !idr.box<@L> -> (!idr.box<@L>) {
    case @N() {
      idr.yield %n : !idr.box<@L>
    }
    case @C(%h: i64, %t: !idr.box<@L>) {
      %h2 = arith.muli %h, %h : i64
      %t2 = func.call @map(%t) : (!idr.box<@L>) -> !idr.box<@L>
      %c = idr.con @L::@C(%h2, %t2) : (i64, !idr.box<@L>) -> !idr.box<@L>
      idr.yield %c : !idr.box<@L>
    }
    }
    return %r : !idr.box<@L>
  }
  func.func private @build(%n: i64) -> !idr.box<@L> {
    %r = idr.match_lit %n : i64 -> (!idr.box<@L>) {
    case 0 {
      %e = idr.constant #idr.con<@L::@N, []> : !idr.box<@L>
      idr.yield %e : !idr.box<@L>
    }
    default {
      %one = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %t = func.call @build(%m) : (i64) -> !idr.box<@L>
      %c = idr.con @L::@C(%n, %t) : (i64, !idr.box<@L>) -> !idr.box<@L>
      idr.yield %c : !idr.box<@L>
    }
    }
    return %r : !idr.box<@L>
  }
  func.func private @sum(%l: !idr.box<@L>, %acc: i64) -> i64 {
    %r = idr.match %l : !idr.box<@L> -> (i64) {
    case @N() {
      idr.yield %acc : i64
    }
    case @C(%h: i64, %t: !idr.box<@L>) {
      %a = arith.addi %acc, %h : i64
      %s = func.call @sum(%t, %a) : (!idr.box<@L>, i64) -> i64
      idr.yield %s : i64
    }
    }
    return %r : i64
  }
  func.func private @both(%a: !idr.str, %b: !idr.str) -> (!idr.data<@Two>, i64) {
    %p = idr.con @Two::@Two(%a, %a) : (!idr.str, !idr.str) -> !idr.data<@Two>
    %n = idr.str.length %b
    return %p, %n : !idr.data<@Two>, i64
  }
  func.func @root(%w: !idr.world) -> !idr.world {
    %c = idr.constant "x" : !idr.str
    %p:2 = func.call @both(%c, %c) : (!idr.str, !idr.str) -> (!idr.data<@Two>, i64)
    %c3 = arith.constant 3 : i64
    %l = func.call @build(%c3) : (i64) -> !idr.box<@L>
    %m = func.call @map(%l) : (!idr.box<@L>) -> !idr.box<@L>
    %z = arith.constant 0 : i64
    %s = func.call @sum(%m, %z) : (!idr.box<@L>, i64) -> i64
    %w2 = idr.io.put_int signed %s, %w : i64
    return %w2 : !idr.world
  }
}
