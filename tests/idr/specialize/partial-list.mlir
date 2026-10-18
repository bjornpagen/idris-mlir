// NEEDS-ACCEPTANCE: that only the entry copy for [1, 2, n] is made and its recursive call passes the tail as a value (inside a recursive component a call keys only the positions passed unchanged along the recursion), with symbol-dce after idr-optimize as the pipeline runs it (S22's parameterless holes).
// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr-optimize,symbol-dce))' -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=one-clone=@sum,calls=@Main.main:@sum -o /dev/null
// A partially static list, [1, 2, n]: its spine and first two elements are
// the static shape, n is a runtime leaf and becomes the copy's parameter.
// The copy's match folds, and its recursive call is on the tail [2, n],
// which is no position passed unchanged along @sum's recursion: the call
// keys nothing of it and passes the tail as a value, to @sum itself. So one
// copy is made, and @sum is still called; a list that a recursion takes
// apart makes no copy per element.
!L = !idr.data<"L", list [@Nil() nil, @Cons(i64, !idr.box<!idr.data<"L">>) cons]>
idr.program @"partial-list" root(@Main.main) stage(first) {
  idr.func @sum(%xs: !idr.box<!L>) -> i64 attributes {total} {
    %r = idr.match %xs : !idr.box<!L> -> (i64) {
    case @Nil() {
      %z = arith.constant 0 : i64
      idr.yield %z : i64
    }
    case @Cons(%h: i64, %t: !idr.box<!L>) {
      %s = idr.call @sum(%t) : (!idr.box<!L>) -> i64
      %a = arith.addi %h, %s : i64
      idr.yield %a : i64
    }
    }
    return %r : i64
  }
  idr.func @use(%n: i64) -> i64 attributes {total} {
    %c1 = arith.constant 1 : i64
    %c2 = arith.constant 2 : i64
    %nil = idr.con !idr.box<!L> @Nil()
    %l3 = idr.con !idr.box<!L> @Cons(%n : i64, %nil : !idr.box<!L>)
    %l2 = idr.con !idr.box<!L> @Cons(%c2 : i64, %l3 : !idr.box<!L>)
    %l1 = idr.con !idr.box<!L> @Cons(%c1 : i64, %l2 : !idr.box<!L>)
    %r = idr.call @sum(%l1) : (!idr.box<!L>) -> i64
    return %r : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %x = arith.extui %c : i32 to i64
    %r = idr.call @use(%x) : (i64) -> i64
    %w2 = idr.io.put_int signed %r, %w1 : i64
    return %w2 : !idr.world
  }
}
