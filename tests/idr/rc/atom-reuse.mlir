// RUN: idris-mlir-opt %s --idr-rc | FileCheck %s
// A constructor without fields is its atom: it has no cell, so a take of
// it hands out no token and a reuse cannot build it. Its laid-out size is
// still the header alone, the size of a boxed constructor whose one field
// is itself an atom (@MkB of a unit), so size alone would pair them: in
// @ended the dead @N would give its non-cell to the @MkB built after it,
// and in @atom the dead @MkB would give its cell to an @N. Neither is a
// reuse site; both constructors stay idr.con.
// CHECK-LABEL: idr.func private @ended(
// CHECK: con @B::@MkB(
// CHECK-NOT: reuse
// CHECK-LABEL: idr.func private @atom(
// CHECK: con @L::@N(
// CHECK-NOT: reuse
// CHECK-LABEL: idr.func @root(
module attributes {idr.program} {
  idr.data @U {
    idr.ctor @MkU ()
  }
  idr.data @B box {
    idr.ctor @MkB (!idr.data<@U>)
  }
  idr.data @L box {
    idr.ctor @N ()
    idr.ctor @C (i64, !idr.box<@L>)
  }
  idr.func private @ended(%l: !idr.box<@L>, %u: !idr.data<@U>) -> !idr.box<@B> {
    %r = idr.match %l : !idr.box<@L> -> (!idr.box<@B>) {
    case @N() {
      %b = idr.con @B::@MkB(%u) : (!idr.data<@U>) -> !idr.box<@B>
      idr.yield %b : !idr.box<@B>
    }
    case @C(%h: i64, %t: !idr.box<@L>) {
      %b = idr.con @B::@MkB(%u) : (!idr.data<@U>) -> !idr.box<@B>
      idr.yield %b : !idr.box<@B>
    }
    }
    return %r : !idr.box<@B>
  }
  idr.func private @atom(%b: !idr.box<@B>) -> !idr.box<@L> {
    %r = idr.match %b : !idr.box<@B> -> (!idr.box<@L>) {
    case @MkB(%u: !idr.data<@U>) {
      %n = idr.con @L::@N() : () -> !idr.box<@L>
      idr.yield %n : !idr.box<@L>
    }
    }
    return %r : !idr.box<@L>
  }
  idr.func @root(%w: !idr.world) -> !idr.world {
    %u = idr.constant #idr.con<@U::@MkU, []> : !idr.data<@U>
    %n = idr.constant #idr.con<@L::@N, []> : !idr.box<@L>
    %b = idr.call @ended(%n, %u) : (!idr.box<@L>, !idr.data<@U>) -> !idr.box<@B>
    %l = idr.call @atom(%b) : (!idr.box<@B>) -> !idr.box<@L>
    %s = idr.match %l : !idr.box<@L> -> (i64) {
    case @N() {
      %z = arith.constant 0 : i64
      idr.yield %z : i64
    }
    case @C(%h: i64, %t: !idr.box<@L>) {
      idr.yield %h : i64
    }
    }
    %w2 = idr.io.put_int signed %s, %w : i64
    return %w2 : !idr.world
  }
}
