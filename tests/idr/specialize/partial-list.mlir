// RUN: idris-mlir-opt %s --idr-optimize -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=no-heap-allocation=@Main.main -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir --idr-expect=holds=not-called=@sum -o /dev/null
// NEEDS-ACCEPTANCE: that the copies for [1, 2, n], [2, n] and [n] are made and inlined into the root, as C09 and C08 decide.
// A partially static list, [1, 2, n]: its spine and first two elements are
// the static shape, n is a runtime leaf and becomes the copy's parameter.
// The copy's match folds and its recursive call is on [2, n], which it
// requests in turn, and so on down to [n]; each copy is called once and on
// no cycle, so it is inlined into the one that asked for it. The call on
// [] is closed and runs at run time, a call of @sum itself. The list is
// @sum's decreasing parameter, and small, so it unrolls: no list is built
// at runtime.
!L = !idr.data<"L", list [@Nil(), @Cons(i64, !idr.box<!idr.data<"L">>)]>
module {
  idr.func private @sum(%xs: !idr.box<!L>) -> i64 attributes {total} {
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
  idr.func private @use(%n: i64) -> i64 attributes {total} {
    %c1 = arith.constant 1 : i64
    %c2 = arith.constant 2 : i64
    %nil = idr.con @Nil() : () -> !idr.box<!L>
    %l3 = idr.con @Cons(%n, %nil) : (i64, !idr.box<!L>) -> !idr.box<!L>
    %l2 = idr.con @Cons(%c2, %l3) : (i64, !idr.box<!L>) -> !idr.box<!L>
    %l1 = idr.con @Cons(%c1, %l2) : (i64, !idr.box<!L>) -> !idr.box<!L>
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
