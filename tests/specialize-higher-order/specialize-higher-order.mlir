// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr-defunctionalize,idr-optimize,symbol-dce),idr-expect{holds=one-clone=@map,not-called=@add,one-clone=@pow,not-called=@inc})' -o /dev/null
// A closure passed to a recursive map, whose function is a fixed
// parameter. After defunctionalization it is a constructor of its sum
// whose label is static and whose capture is a runtime leaf: the copy of
// @map rebuilds it over a new parameter, its dispatch folds to a call of
// @add, which it inlines, and the recursive call, which passes the same
// constructor, has the copy's key and calls the copy itself. One copy
// serves the whole recursion, and @map itself is no longer called.
// A closure with no capture, @inc passed to the recursive @pow, is one
// label too: @pow is specialized on it, the copy's dispatch has one arm, a
// direct call of @inc, which it inlines, and every call of @pow reaches
// the one copy. Each function carries the location Emit gives it, its
// definition's name, by which a copy names what it was made from.
!L = !idr.data<"L", list [@Nil() nil, @Cons(i64, !idr.box<!idr.data<"L">>) cons]>
idr.program @"higher-order" root(@Main.main) stage(higher) {
  idr.func @add(%a: i64, %x: i64) -> i64 attributes {total} {
    %y = arith.addi %a, %x : i64
    return %y : i64
  } loc("add")
  idr.func @map(%f: !idr.fn<(i64) -> (i64)>, %xs: !idr.box<!L>) -> !idr.box<!L> attributes {total} {
    %r = idr.match %xs : !idr.box<!L> -> (!idr.box<!L>) {
    case @Nil() {
      %n = idr.con !idr.box<!L> @Nil()
      idr.yield %n : !idr.box<!L>
    }
    case @Cons(%h: i64, %t: !idr.box<!L>) {
      %h2 = idr.apply %f(%h) : !idr.fn<(i64) -> (i64)>
      %t2 = idr.call @map(%f, %t) : (!idr.fn<(i64) -> (i64)>, !idr.box<!L>) -> !idr.box<!L>
      %c = idr.con !idr.box<!L> @Cons(%h2 : i64, %t2 : !idr.box<!L>)
      idr.yield %c : !idr.box<!L>
    }
    }
    return %r : !idr.box<!L>
  } loc("map")
  idr.func @use(%n: i64, %xs: !idr.box<!L>) -> !idr.box<!L> attributes {total} {
    %f = idr.closure @add(%n) : (i64) -> !idr.fn<(i64) -> (i64)>
    %r = idr.call @map(%f, %xs) : (!idr.fn<(i64) -> (i64)>, !idr.box<!L>) -> !idr.box<!L>
    return %r : !idr.box<!L>
  } loc("use")
  idr.func @inc(%x: i64) -> i64 attributes {total} {
    %c1 = arith.constant 1 : i64
    %y = arith.addi %x, %c1 : i64
    return %y : i64
  } loc("inc")
  idr.func @pow(%f: !idr.fn<(i64) -> (i64)>, %n: i64, %x: i64) -> i64 attributes {total} {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %x : i64
    }
    default(%d: i64) {
      %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %r = idr.call @pow(%f, %m, %y) : (!idr.fn<(i64) -> (i64)>, i64, i64) -> i64
      idr.yield %r : i64
    }
    }
    return %r : i64
  } loc("pow")
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %xs = idr.call @read(%n) : (i64) -> !idr.box<!L>
    %r = idr.call @use(%n, %xs) : (i64, !idr.box<!L>) -> !idr.box<!L>
    %s = idr.call @first(%r) : (!idr.box<!L>) -> i64
    %w2 = idr.io.put_sint %s, %w1 : i64
    %inc = idr.closure @inc() : () -> !idr.fn<(i64) -> (i64)>
    %p = idr.call @pow(%inc, %n, %n) : (!idr.fn<(i64) -> (i64)>, i64, i64) -> i64
    %w3 = idr.io.put_sint %p, %w2 : i64
    return %w3 : !idr.world
  } loc("Main.main")
  // A list known only at runtime: a loop, which nothing inlines.
  idr.func @read(%n: i64) -> !idr.box<!L> {
    %r = idr.match_lit %n : i64 -> (!idr.box<!L>) {
    case 0 {
      %nil = idr.con !idr.box<!L> @Nil()
      idr.yield %nil : !idr.box<!L>
    }
    default(%d: i64) {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %t = idr.call @read(%m) : (i64) -> !idr.box<!L>
      %xs = idr.con !idr.box<!L> @Cons(%n : i64, %t : !idr.box<!L>)
      idr.yield %xs : !idr.box<!L>
    }
    }
    return %r : !idr.box<!L>
  } loc("read")
  idr.func @first(%xs: !idr.box<!L>) -> i64 attributes {total} {
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
  } loc("first")
}
