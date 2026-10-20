// RUN: idris-mlir-opt %s --test-idr-facts -verify-diagnostics=only-expected -o /dev/null
// RUN: idris-mlir-opt %s --cse --canonicalize --idr-expect=holds=computes-nothing=@dead -o /dev/null
// Ops that allocate their result (a box's idr.con, string builders, big
// ops) are two values when they are written twice, so that no two cells
// become one: they may move, and an unused one is dead code, but two equal
// ones do not merge. Every op that builds a string or a big is such an op
// (@builders, one of each). An unboxed constructor has no effect at all:
// equal ones are one value; so are the ops that only read a string or a
// big into a word, a Double or a Bool, and a natural as the Integer it
// already is (@reads, one of each), which merge.
// After the folds and dead code removal, nothing of a function whose every
// result is unused is left.

!P = !idr.data<"P">
!L = !idr.data<"L">
#types = #idr.types<
  "L" = list [@Nil() nil, @Cons(i64, !idr.box<!idr.data<"L">>) cons],
  "P" = plain [@MkP(i64, i64)]
>
idr.program @alloc root(@root) stage(first) types #types {
  idr.func @merged(%x: i64) -> (!P, !P) {
    // expected-remark @below {{facts: [move delay merge]}}
    %a = idr.con !P @MkP(%x : i64, %x : i64)
    // expected-remark @below {{facts: [move delay merge]}}
    %b = idr.con !P @MkP(%x : i64, %x : i64)
    return %a, %b : !P, !P
  }
  idr.func @cells(%x: i64, %l: !idr.box<!L>, %s: !idr.str, %g: !idr.big, %nat: !idr.nat)
      -> (!idr.box<!L>, !idr.box<!L>, !idr.str, !idr.str, !idr.big, !idr.big, !idr.nat, !idr.nat) {
    // expected-remark @below {{facts: [move delay]}}
    %a = idr.con !idr.box<!L> @Cons(%x : i64, %l : !idr.box<!L>)
    // expected-remark @below {{facts: [move delay]}}
    %b = idr.con !idr.box<!L> @Cons(%x : i64, %l : !idr.box<!L>)
    // expected-remark @below {{facts: [move delay]}}
    %c = idr.str.append %s, %s
    // expected-remark @below {{facts: [move delay]}}
    %d = idr.str.append %s, %s
    // expected-remark @below {{facts: [move delay]}}
    %e = idr.big.add %g, %g
    // expected-remark @below {{facts: [move delay]}}
    %f = idr.big.add %g, %g
    // expected-remark @below {{facts: [move delay]}}
    %p = idr.big.pred %nat
    // expected-remark @below {{facts: [move delay]}}
    %q = idr.big.pred %nat
    return %a, %b, %c, %d, %e, %f, %p, %q
        : !idr.box<!L>, !idr.box<!L>, !idr.str, !idr.str, !idr.big, !idr.big, !idr.nat, !idr.nat
  }
  idr.func @builders(%x: i64, %s: !idr.str, %g: !idr.big, %c: i32, %u: f64, %nat: !idr.nat)
      -> (!idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.big, !idr.big, !idr.big, !idr.big, !idr.big, !idr.big, !idr.str, !idr.big, !idr.nat) {
    // expected-remark @below {{facts: [move delay]}}
    %d = idr.str.cons %c, %s
    // expected-remark @below {{facts: [move delay]}}
    %e = idr.str.from_char %c
    // expected-remark @below {{facts: [move delay]}}
    %f = idr.str.show_sint %x : i64
    // expected-remark @below {{facts: [move delay]}}
    %su = idr.str.show_uint %x : i64
    // expected-remark @below {{facts: [move delay]}}
    %sd = idr.str.show_double %u
    // expected-remark @below {{facts: [move delay]}}
    %h = idr.str.substr %s, %x, %x
    // expected-remark @below {{facts: [move delay]}}
    %i = idr.str.reverse %s
    // expected-remark @below {{facts: [move delay]}}
    %ap = idr.str.append %s, %s
    // expected-remark @below {{facts: [move delay]}}
    %j = idr.big.mul %g, %g
    // expected-remark @below {{facts: [move delay]}}
    %sub = idr.big.sub %g, %g
    // expected-remark @below {{facts: [move delay]}}
    %k = idr.big.neg %g
    // expected-remark @below {{facts: [move delay]}}
    %m = idr.big.from_sint %x : i64
    // expected-remark @below {{facts: [move delay]}}
    %mu = idr.big.from_uint %x : i64
    // expected-remark @below {{facts: [move delay]}}
    %fd = idr.big.from_double %u
    // expected-remark @below {{facts: [move delay]}}
    %n = idr.big.show %g
    // expected-remark @below {{facts: [move delay]}}
    %o = idr.big.from_str %s
    // expected-remark @below {{facts: [move delay]}}
    %bn = idr.nat.from_big %g
    return %d, %e, %f, %su, %sd, %h, %i, %ap, %j, %sub, %k, %m, %mu, %fd, %n, %o, %bn
        : !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.big, !idr.big, !idr.big, !idr.big, !idr.big, !idr.big, !idr.str, !idr.big, !idr.nat
  }
  idr.func @reads(%x: i64, %s: !idr.str, %g: !idr.big, %nat: !idr.nat) -> (i64, i1, i1, i32, f64, i64, f64, i32, i64, !idr.big) {
    // expected-remark @below {{facts: [move delay merge]}}
    %p = idr.str.length %s
    // expected-remark @below {{facts: [move delay merge]}}
    %q = idr.str.cmp lt %s, %s
    // expected-remark @below {{facts: [move delay merge]}}
    %r = idr.big.cmp eq %g, %g
    // expected-remark @below {{facts: [move delay merge]}}
    %t = idr.big.to_int %g : i32
    // expected-remark @below {{facts: [move delay merge]}}
    %u2 = idr.big.to_double %g
    // expected-remark @below {{facts: [move delay merge]}}
    %v = idr.str.to_int %s : i64
    // expected-remark @below {{facts: [move delay merge]}}
    %w = idr.str.to_double %s
    // expected-remark @below {{facts: [move delay merge]}}
    %y = idr.int_head_s %x : i64
    // expected-remark @below {{facts: [move delay merge]}}
    %bl = idr.str.bytes_length %s
    // expected-remark @below {{facts: [move delay merge]}}
    %nb = idr.nat.to_big %nat
    return %p, %q, %r, %t, %u2, %v, %w, %y, %bl, %nb : i64, i1, i1, i32, f64, i64, f64, i32, i64, !idr.big
  }
  idr.func @dead(%x: i64, %l: !idr.box<!L>, %s: !idr.str, %g: !idr.big, %c: i32, %nat: !idr.nat) {
    %a = idr.con !idr.box<!L> @Cons(%x : i64, %l : !idr.box<!L>)
    %b = idr.str.append %s, %s
    %d = idr.str.cons %c, %s
    %e = idr.str.from_char %c
    %f = idr.str.show_sint %x : i64
    %h = idr.str.substr %s, %x, %x
    %i = idr.str.reverse %s
    %j = idr.big.mul %g, %g
    %k = idr.big.neg %g
    %z = idr.big.pred %nat
    %m = idr.big.from_sint %x : i64
    %n = idr.big.show %g
    %o = idr.big.from_str %s
    %p = idr.str.length %s
    %q = idr.str.cmp lt %s, %s
    %r = idr.big.cmp eq %g, %g
    %t = idr.big.to_int %g : i32
    %u = idr.big.to_double %g
    %v = idr.str.to_int %s : i64
    %w = idr.str.to_double %s
    %y = idr.int_head_s %x : i64
    return
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
