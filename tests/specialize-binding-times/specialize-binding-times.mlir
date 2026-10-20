// RUN: idris-mlir-opt %s --idr-defunctionalize --idr-binding-times -verify-diagnostics -o /dev/null
// The binding time of each parameter, as the specialization requests read
// it: fixed when every call of the function from its own cycle of calls
// passes the parameter back in its own position, through an op that only
// changes its grade or a match's default region; varies otherwise. A
// function on no cycle meets no such call, so every parameter is fixed.
// Defunctionalization runs first: binding times are read over the calls
// between the members of a cycle, and a closure is then a constructor of
// its sum like any other value.
!L = !idr.data<"L">
#types = #idr.types<
  "L" = list [@Nil() nil, @Cons(i64, !idr.box<!idr.data<"L">>) cons]
>
idr.program @"binding-times" root(@Main.main) stage(higher) types #types {
  // map f (x :: xs) = f x :: map f xs: f is passed back, xs is not.
  // expected-remark @below {{@map: fixed, varies}}
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
  // count acc n = count (acc + 1) (n - 1): an accumulator and a counter.
  // expected-remark @below {{@count: varies, varies}}
  idr.func @count(%acc: i64, %n: !idr.big) -> i64 {
    %r = idr.match_lit %n : !idr.big -> (i64) {
    case #idr.big<0> {
      idr.yield %acc : i64
    }
    default(%d: !idr.big) {
      %c1 = arith.constant 1 : i64
      %one = idr.constant !idr.big #idr.big<1>
      %a = arith.addi %acc, %c1 : i64
      %m = idr.big.sub %n, %one
      %x = idr.call @count(%a, %m) : (i64, !idr.big) -> i64
      idr.yield %x : i64
    }
    }
    return %r : i64
  }
  // After defunctionalization each apply is a match on the closure's sum,
  // whose one label is @twice: @twice calls itself on its closure's
  // capture, and on what its first call gave.
  // expected-remark @below {{@twice: varies, varies}}
  idr.func @twice(%f: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 {
    %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
    %z = idr.apply %f(%y) : !idr.fn<(i64) -> (i64)>
    return %z : i64
  }
  // iter f n x = iter (twice f) (n - 1) x: a closure rebuilt on every
  // iteration and a counter vary, x is passed back.
  // expected-remark @below {{@iter: varies, varies, fixed}}
  idr.func @iter(%f: !idr.fn<(i64) -> (i64)>, %n: i64, %x: i64) -> i64 {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
      idr.yield %y : i64
    }
    default(%d: i64) {
      %g = idr.closure @twice(%f) : (!idr.fn<(i64) -> (i64)>) -> !idr.fn<(i64) -> (i64)>
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %y = idr.call @iter(%g, %m, %x) : (!idr.fn<(i64) -> (i64)>, i64, i64) -> i64
      idr.yield %y : i64
    }
    }
    return %r : i64
  }
  // walk xs 0 = walk xs 1; walk (_ :: t) _ = walk t 0: xs is passed back
  // once and its tail once.
  // expected-remark @below {{@walk: varies, varies}}
  idr.func @walk(%xs: !idr.box<!L>, %flag: i64) -> i64 {
    %r = idr.match_lit %flag : i64 -> (i64) {
    case 0 {
      %c1 = arith.constant 1 : i64
      %y = idr.call @walk(%xs, %c1) : (!idr.box<!L>, i64) -> i64
      idr.yield %y : i64
    }
    default(%d: i64) {
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
  // even and odd, each taking the tail of its list to the other.
  // expected-remark @below {{@even: varies}}
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
  // expected-remark @below {{@odd: varies}}
  idr.func @odd(%xs: !idr.box<!L>) -> i1 {
    %t = idr.field %xs : !idr.box<!L> @Cons[1] -> !idr.box<!L>
    %y = idr.call @even(%t) : (!idr.box<!L>) -> i1
    return %y : i1
  }
  // thread s n: s passed back through its one use and its entry again,
  // n counting down.
  // expected-remark @below {{@thread: fixed, varies}}
  idr.func @thread(%s: !idr.lin<!idr.str>, %n: i64) -> i64 {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      %u = idr.lin.use %s : !idr.lin<!idr.str>
      %l = idr.str.length %u
      idr.yield %l : i64
    }
    default(%d: i64) {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %d, %c1 : i64
      %u = idr.lin.use %s : !idr.lin<!idr.str>
      %e = idr.lin.enter %u : !idr.lin<!idr.str>
      %y = idr.call @thread(%e, %m) : (!idr.lin<!idr.str>, i64) -> i64
      idr.yield %y : i64
    }
    }
    return %r : i64
  }
  // spin n = spin n, through the default region of a match on n: the
  // region's value is n itself, passed back.
  // expected-remark @below {{@spin: fixed}}
  idr.func @spin(%n: i64) -> i64 {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %n : i64
    }
    default(%d: i64) {
      %y = idr.call @spin(%d) : (i64) -> i64
      idr.yield %y : i64
    }
    }
    return %r : i64
  }
  // swap a b = swap b a: each passed back, but in the other's position.
  // expected-remark @below {{@swap: varies, varies}}
  idr.func @swap(%a: i64, %b: i64) -> i64 {
    %r = idr.match_lit %a : i64 -> (i64) {
    case 0 {
      idr.yield %b : i64
    }
    default(%d: i64) {
      %y = idr.call @swap(%b, %a) : (i64, i64) -> i64
      idr.yield %y : i64
    }
    }
    return %r : i64
  }
  // A function on no cycle.
  // expected-remark @below {{@plus: fixed, fixed}}
  idr.func @plus(%a: i64, %b: i64) -> i64 {
    %c = arith.addi %a, %b : i64
    return %c : i64
  }
  // expected-remark @below {{@Main.main:}}
  idr.func @Main.main() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}
