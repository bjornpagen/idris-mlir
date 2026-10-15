// RUN: idris-mlir-opt %s --idr-defunctionalize --idr-optimize -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=one-clone=@map,not-called=@add -o /dev/null
// RUN: FileCheck %s --implicit-check-not='call @map(' < %t.mlir
// NEEDS-ACCEPTANCE: that @map is specialized on the known constructor of @add with its capture a hole, as C09 decides.
// A closure passed to a recursive map, whose function is a fixed
// parameter. After defunctionalization it is a constructor of its sum
// whose label is static and whose capture is a runtime leaf: the copy of
// @map rebuilds it over a new parameter, its dispatch folds to a call of
// @add, which it inlines, and the recursive call, which passes the same
// constructor, has the copy's key and calls the copy itself. One copy
// serves the whole recursion, and @map itself is no longer called.
// CHECK: idr.func @Main.main(
!L = !idr.data<"L", list [@Nil(), @Cons(i64, !idr.box<!idr.data<"L">>)]>
module {
  idr.func private @add(%a: i64, %x: i64) -> i64 attributes {total} {
    %y = arith.addi %a, %x : i64
    return %y : i64
  }
  idr.func private @map(%f: !idr.fn<(i64) -> (i64)>, %xs: !idr.box<!L>) -> !idr.box<!L> attributes {total} {
    %r = idr.match %xs : !idr.box<!L> -> (!idr.box<!L>) {
    case @Nil() {
      %n = idr.con @Nil() : () -> !idr.box<!L>
      idr.yield %n : !idr.box<!L>
    }
    case @Cons(%h: i64, %t: !idr.box<!L>) {
      %h2 = idr.apply %f(%h) : !idr.fn<(i64) -> (i64)>
      %t2 = idr.call @map(%f, %t) : (!idr.fn<(i64) -> (i64)>, !idr.box<!L>) -> !idr.box<!L>
      %c = idr.con @Cons(%h2, %t2) : (i64, !idr.box<!L>) -> !idr.box<!L>
      idr.yield %c : !idr.box<!L>
    }
    }
    return %r : !idr.box<!L>
  } loc("map")
  idr.func private @use(%n: i64, %xs: !idr.box<!L>) -> !idr.box<!L> attributes {total} {
    %f = idr.closure @add(%n) : (i64) -> !idr.fn<(i64) -> (i64)>
    %r = idr.call @map(%f, %xs) : (!idr.fn<(i64) -> (i64)>, !idr.box<!L>) -> !idr.box<!L>
    return %r : !idr.box<!L>
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %xs = idr.call @read(%n) : (i64) -> !idr.box<!L>
    %r = idr.call @use(%n, %xs) : (i64, !idr.box<!L>) -> !idr.box<!L>
    %s = idr.call @first(%r) : (!idr.box<!L>) -> i64
    %w2 = idr.io.put_int signed %s, %w1 : i64
    return %w2 : !idr.world
  }
  // A list known only at runtime: a loop, which nothing inlines.
  idr.func private @read(%n: i64) -> !idr.box<!L> {
    %r = idr.match_lit %n : i64 -> (!idr.box<!L>) {
    case 0 {
      %nil = idr.con @Nil() : () -> !idr.box<!L>
      idr.yield %nil : !idr.box<!L>
    }
    default {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %t = idr.call @read(%m) : (i64) -> !idr.box<!L>
      %xs = idr.con @Cons(%n, %t) : (i64, !idr.box<!L>) -> !idr.box<!L>
      idr.yield %xs : !idr.box<!L>
    }
    }
    return %r : !idr.box<!L>
  }
  idr.func private @first(%xs: !idr.box<!L>) -> i64 attributes {total} {
    %r = idr.match %xs : !idr.box<!L> -> (i64) {
    case @Nil() {
      %z = arith.constant 0 : i64
      idr.yield %z : i64
    }
    case @Cons(%h: i64, %t: !idr.box<!L>) {
      idr.yield %h : i64
    }
    }
    return %r : i64
  }
}
