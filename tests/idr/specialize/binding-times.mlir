// RUN: idris-mlir-opt %s --idr-binding-times -o %t.mlir 2> %t.err
// RUN: FileCheck %s < %t.err
// The binding time of each parameter, as idr-specialize decides on it.
// map f (x :: xs) = f x :: map f xs: f is fixed, xs decreasing.
// CHECK-DAG: remark: @map: fixed, decreasing
// count acc n = count (acc + 1) (n - 1): an accumulator and a counter.
// CHECK-DAG: remark: @count: other, other
// iter f n x = iter (twice f) (n - 1) x: a closure rebuilt on every
// iteration is no fixed parameter, x is.
// CHECK-DAG: remark: @iter: other, other, fixed
// walk xs 0 = walk xs 1; walk (_ :: t) _ = walk t 0: xs is passed itself
// and a part of itself, so its keys are parts of the first.
// CHECK-DAG: remark: @walk: bounded, other
// even and odd, each taking the tail of its list to the other.
// CHECK-DAG: remark: @even: decreasing
// CHECK-DAG: remark: @odd: decreasing
// A loop through a closure: @loop builds a closure of @again, which calls
// @loop back with what it captured. Recursion through a closure counts, and
// what the closure's applies pass may be anything.
// CHECK-DAG: remark: @loop: fixed
// CHECK-DAG: remark: @again: fixed, other
// A function on no cycle specializes on anything.
// CHECK-DAG: remark: @twice: free, free
module attributes {idr.program} {
  idr.data @L box {
    idr.ctor @Nil tag 0 () {quantities = []}
    idr.ctor @Cons tag 1 (i64, !idr.box<@L>) {quantities = ["w", "w"]}
  }
  func.func private @map(%f: !idr.fn<(i64) -> (i64)> {idr.quantity = "w"}, %xs: !idr.box<@L> {idr.quantity = "w"}) -> !idr.box<@L> {
    %r = idr.match %xs : !idr.box<@L> -> (!idr.box<@L>) {
    case @Nil() {
      idr.yield %xs : !idr.box<@L>
    }
    case @Cons(%h: i64, %t: !idr.box<@L>) {
      %h2 = idr.apply %f(%h) : !idr.fn<(i64) -> (i64)>
      %t2 = func.call @map(%f, %t) : (!idr.fn<(i64) -> (i64)>, !idr.box<@L>) -> !idr.box<@L>
      %c = idr.con @L::@Cons(%h2, %t2) : (i64, !idr.box<@L>) -> !idr.box<@L>
      idr.yield %c : !idr.box<@L>
    }
    }
    return %r : !idr.box<@L>
  }
  func.func private @count(%acc: i64 {idr.quantity = "w"}, %n: !idr.big {idr.quantity = "w"}) -> i64 {
    %r = idr.match_lit %n : !idr.big -> (i64) {
    case #idr.big<"0"> {
      idr.yield %acc : i64
    }
    default {
      %c1 = arith.constant 1 : i64
      %one = idr.constant #idr.big<"1"> : !idr.big
      %a = arith.addi %acc, %c1 : i64
      %m = idr.big.sub %n, %one
      %x = func.call @count(%a, %m) : (i64, !idr.big) -> i64
      idr.yield %x : i64
    }
    }
    return %r : i64
  }
  func.func private @twice(%f: !idr.fn<(i64) -> (i64)> {idr.quantity = "w"}, %x: i64 {idr.quantity = "w"}) -> i64 {
    %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
    %z = idr.apply %f(%y) : !idr.fn<(i64) -> (i64)>
    return %z : i64
  }
  func.func private @iter(%f: !idr.fn<(i64) -> (i64)> {idr.quantity = "w"}, %n: i64 {idr.quantity = "w"}, %x: i64 {idr.quantity = "w"}) -> i64 {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
      idr.yield %y : i64
    }
    default {
      %g = idr.closure @twice(%f) : (!idr.fn<(i64) -> (i64)>) -> !idr.fn<(i64) -> (i64)>
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %y = func.call @iter(%g, %m, %x) : (!idr.fn<(i64) -> (i64)>, i64, i64) -> i64
      idr.yield %y : i64
    }
    }
    return %r : i64
  }
  func.func private @walk(%xs: !idr.box<@L> {idr.quantity = "w"}, %flag: i64 {idr.quantity = "w"}) -> i64 {
    %r = idr.match_lit %flag : i64 -> (i64) {
    case 0 {
      %c1 = arith.constant 1 : i64
      %y = func.call @walk(%xs, %c1) : (!idr.box<@L>, i64) -> i64
      idr.yield %y : i64
    }
    default {
      %s = idr.match %xs : !idr.box<@L> -> (i64) {
      case @Nil() {
        idr.yield %flag : i64
      }
      case @Cons(%h: i64, %t: !idr.box<@L>) {
        %c0 = arith.constant 0 : i64
        %y = func.call @walk(%t, %c0) : (!idr.box<@L>, i64) -> i64
        idr.yield %y : i64
      }
      }
      idr.yield %s : i64
    }
    }
    return %r : i64
  }
  func.func private @even(%xs: !idr.box<@L> {idr.quantity = "w"}) -> i1 {
    %r = idr.match %xs : !idr.box<@L> -> (i1) {
    case @Nil() {
      %t = arith.constant true
      idr.yield %t : i1
    }
    case @Cons(%h: i64, %t: !idr.box<@L>) {
      %y = func.call @odd(%t) : (!idr.box<@L>) -> i1
      idr.yield %y : i1
    }
    }
    return %r : i1
  }
  func.func private @odd(%xs: !idr.box<@L> {idr.quantity = "w"}) -> i1 {
    %t = idr.field %xs[@Cons, 1] : !idr.box<@L> -> !idr.box<@L>
    %y = func.call @even(%t) : (!idr.box<@L>) -> i1
    return %y : i1
  }
  func.func private @loop(%n: i64 {idr.quantity = "w"}) -> !idr.fn<(i64) -> (i64)> {
    %k = idr.closure @again(%n) : (i64) -> !idr.fn<(i64) -> (i64)>
    return %k : !idr.fn<(i64) -> (i64)>
  }
  func.func private @again(%n: i64 {idr.quantity = "w"}, %x: i64 {idr.quantity = "w"}) -> i64 {
    %k = func.call @loop(%n) : (i64) -> !idr.fn<(i64) -> (i64)>
    %y = idr.apply %k(%x) : !idr.fn<(i64) -> (i64)>
    return %y : i64
  }
  func.func @Main.main() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}
