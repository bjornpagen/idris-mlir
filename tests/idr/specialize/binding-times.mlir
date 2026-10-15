// RUN: idris-mlir-opt %s --idr-defunctionalize --idr-binding-times -o %t.mlir 2> %t.err
// RUN: FileCheck %s < %t.err
// NEEDS-ACCEPTANCE: the remark text of each binding time, after defunctionalization made each closure a constructor.
// The binding time of each parameter, as the specialization requests read
// it. Defunctionalization runs first: binding times are read over the
// calls between the members of a cycle, and a closure is then a
// constructor of its sum like any other value.
// map f (x :: xs) = f x :: map f xs: f is fixed, xs decreasing.
// CHECK-DAG: remark: @map: fixed, decreasing
// count acc n = count (acc + 1) (n - 1): an accumulator and a counter.
// CHECK-DAG: remark: @count: other, other
// iter f n x = iter (twice f) (n - 1) x: a closure rebuilt on every
// iteration is no fixed parameter, x is, and the Int n counts down.
// CHECK-DAG: remark: @iter: other, decreasing, fixed
// walk xs 0 = walk xs 1; walk (_ :: t) _ = walk t 0: xs is passed itself
// and a part of itself, so its keys are parts of the first.
// CHECK-DAG: remark: @walk: bounded, other
// even and odd, each taking the tail of its list to the other.
// CHECK-DAG: remark: @even: decreasing
// CHECK-DAG: remark: @odd: decreasing
// A function on no cycle specializes on anything. (@twice is on one after
// defunctionalization: the dispatch of its closure calls itself.)
// CHECK-DAG: remark: @plus: free, free
!L = !idr.data<"L", list [@Nil() nil, @Cons(i64, !idr.box<!idr.data<"L">>) cons]>
idr.program @"binding-times" root(@Main.main) stage(higher) {
  idr.func @map(%f: !idr.fn<(i64) -> (i64)>, %xs: !idr.box<!L>) -> !idr.box<!L> {
    %r = idr.match %xs : !idr.box<!L> -> (!idr.box<!L>) {
    case @Nil() {
      idr.yield %xs : !idr.box<!L>
    }
    case @Cons(%h: i64, %t: !idr.box<!L>) {
      %h2 = idr.apply %f(%h) : !idr.fn<(i64) -> (i64)>
      %t2 = idr.call @map(%f, %t) : (!idr.fn<(i64) -> (i64)>, !idr.box<!L>) -> !idr.box<!L>
      %c = idr.con !idr.box<!L> @Cons(%h2 : i64, %t2 : !idr.box<!L>)
      idr.yield %c : !idr.box<!L>
    }
    }
    return %r : !idr.box<!L>
  }
  idr.func @count(%acc: i64, %n: !idr.big) -> i64 {
    %r = idr.match_lit %n : !idr.big -> (i64) {
    case #idr.big<0> {
      idr.yield %acc : i64
    }
    default {
      %c1 = arith.constant 1 : i64
      %one = idr.constant #idr.big<1> : !idr.big
      %a = arith.addi %acc, %c1 : i64
      %m = idr.big.sub %n, %one
      %x = idr.call @count(%a, %m) : (i64, !idr.big) -> i64
      idr.yield %x : i64
    }
    }
    return %r : i64
  }
  idr.func @twice(%f: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 {
    %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
    %z = idr.apply %f(%y) : !idr.fn<(i64) -> (i64)>
    return %z : i64
  }
  idr.func @iter(%f: !idr.fn<(i64) -> (i64)>, %n: i64, %x: i64) -> i64 {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
      idr.yield %y : i64
    }
    default {
      %g = idr.closure @twice(%f) : (!idr.fn<(i64) -> (i64)>) -> !idr.fn<(i64) -> (i64)>
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %y = idr.call @iter(%g, %m, %x) : (!idr.fn<(i64) -> (i64)>, i64, i64) -> i64
      idr.yield %y : i64
    }
    }
    return %r : i64
  }
  idr.func @walk(%xs: !idr.box<!L>, %flag: i64) -> i64 {
    %r = idr.match_lit %flag : i64 -> (i64) {
    case 0 {
      %c1 = arith.constant 1 : i64
      %y = idr.call @walk(%xs, %c1) : (!idr.box<!L>, i64) -> i64
      idr.yield %y : i64
    }
    default {
      %s = idr.match %xs : !idr.box<!L> -> (i64) {
      case @Nil() {
        idr.yield %flag : i64
      }
      case @Cons(%h: i64, %t: !idr.box<!L>) {
        %c0 = arith.constant 0 : i64
        %y = idr.call @walk(%t, %c0) : (!idr.box<!L>, i64) -> i64
        idr.yield %y : i64
      }
      }
      idr.yield %s : i64
    }
    }
    return %r : i64
  }
  idr.func @even(%xs: !idr.box<!L>) -> i1 {
    %r = idr.match %xs : !idr.box<!L> -> (i1) {
    case @Nil() {
      %t = arith.constant true
      idr.yield %t : i1
    }
    case @Cons(%h: i64, %t: !idr.box<!L>) {
      %y = idr.call @odd(%t) : (!idr.box<!L>) -> i1
      idr.yield %y : i1
    }
    }
    return %r : i1
  }
  idr.func @odd(%xs: !idr.box<!L>) -> i1 {
    %t = idr.field %xs : !idr.box<!L> @Cons[1] -> !idr.box<!L>
    %y = idr.call @even(%t) : (!idr.box<!L>) -> i1
    return %y : i1
  }
  idr.func @plus(%a: i64, %b: i64) -> i64 {
    %c = arith.addi %a, %b : i64
    return %c : i64
  }
  idr.func @Main.main() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}
