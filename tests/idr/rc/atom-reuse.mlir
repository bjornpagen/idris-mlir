// RUN: idris-mlir-opt %s --idr-rc | FileCheck %s
// A constructor without fields is its atom: it has no cell, so a take of
// it hands out no token and a reuse cannot build it. Its laid-out size is
// still the header alone, the size of a boxed constructor whose one field
// is itself an atom (@MkB of a unit), so size alone would pair them: in
// @ended the dead @N would give its non-cell to the @MkB built after it,
// and in @atom the dead @MkB would give its cell to an @N. Neither is a
// reuse site; both constructors stay idr.con.
// CHECK-LABEL: idr.func @ended(
// CHECK: con {{.*}}@MkB(
// CHECK-NOT: reuse
// CHECK-LABEL: idr.func @atom(
// CHECK: con {{.*}}@N(
// CHECK-NOT: reuse
// CHECK-LABEL: idr.func @root(
!U = !idr.data<"U", plain [@MkU()]>
!B = !idr.data<"B", plain [@MkB(!U)]>
!L = !idr.data<"L", list [@N() nil, @C(i64, !idr.box<!idr.data<"L">>) cons]>
idr.program @"atom-reuse" root(@root) stage(first) {
  idr.func @ended(%l: !idr.box<!L>, %u: !U) -> !idr.box<!B> {
    %r = idr.match %l : !idr.box<!L> -> (!idr.box<!B>) {
    case @N() {
      %b = idr.con !idr.box<!B> @MkB(%u : !U)
      idr.yield %b : !idr.box<!B>
    }
    case @C(%h: i64, %t: !idr.box<!L>) {
      %b = idr.con !idr.box<!B> @MkB(%u : !U)
      idr.yield %b : !idr.box<!B>
    }
    }
    return %r : !idr.box<!B>
  }
  idr.func @atom(%b: !idr.box<!B>) -> !idr.box<!L> {
    %r = idr.match %b : !idr.box<!B> -> (!idr.box<!L>) {
    case @MkB(%u: !U) {
      %n = idr.con !idr.box<!L> @N()
      idr.yield %n : !idr.box<!L>
    }
    }
    return %r : !idr.box<!L>
  }
  idr.func @root(%w: !idr.world) -> !idr.world {
    %u = idr.constant #idr.con<@MkU, []> : !U
    %n = idr.constant #idr.con<@N, []> : !idr.box<!L>
    %b = idr.call @ended(%n, %u) : (!idr.box<!L>, !U) -> !idr.box<!B>
    %l = idr.call @atom(%b) : (!idr.box<!B>) -> !idr.box<!L>
    %s = idr.match %l : !idr.box<!L> -> (i64) {
    case @N() {
      %z = arith.constant 0 : i64
      idr.yield %z : i64
    }
    case @C(%h: i64, %t: !idr.box<!L>) {
      idr.yield %h : i64
    }
    }
    %w2 = idr.io.put_int signed %s, %w : i64
    return %w2 : !idr.world
  }
}
