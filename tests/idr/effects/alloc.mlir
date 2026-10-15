// RUN: idris-mlir-opt %s --idr-expect=holds=facts-as-marked -o /dev/null
// RUN: idris-mlir-opt %s --cse --canonicalize --idr-expect=holds=computes-nothing=@dead -o /dev/null
// NEEDS-ACCEPTANCE: each op's answers are its own declared effects (R02); check each mark against them.
// Ops that allocate their result (a box's idr.con, string builders, big
// ops) are two values when they are written twice, so that no two cells
// become one: they may move, and an unused one is dead code, but two equal
// ones do not merge. An unboxed constructor has no effect at all: equal
// ones are one value. After the folds and dead code removal, nothing of a
// function whose every result is unused is left.

!P = !idr.data<"P", plain [@MkP(i64, i64)]>
!L = !idr.data<"L", list [@Nil() nil, @Cons(i64, !idr.box<!idr.data<"L">>) cons]>
idr.program @alloc root(@root) stage(first) {
  idr.func @merged(%x: i64) -> (!P, !P) {
    %a = idr.con !P @MkP(%x : i64, %x : i64) {expect.facts = "move delay merge"}
    %b = idr.con !P @MkP(%x : i64, %x : i64) {expect.facts = "move delay merge"}
    return %a, %b : !P, !P
  }
  idr.func @cells(%x: i64, %l: !idr.box<!L>, %s: !idr.str, %g: !idr.big, %nat: !idr.nat)
      -> (!idr.box<!L>, !idr.box<!L>, !idr.str, !idr.str, !idr.big, !idr.big, !idr.nat, !idr.nat) {
    %a = idr.con !idr.box<!L> @Cons(%x : i64, %l : !idr.box<!L>) {expect.facts = "move delay"}
    %b = idr.con !idr.box<!L> @Cons(%x : i64, %l : !idr.box<!L>) {expect.facts = "move delay"}
    %c = idr.str.append %s, %s {expect.facts = "move delay"}
    %d = idr.str.append %s, %s {expect.facts = "move delay"}
    %e = idr.big.add %g, %g {expect.facts = "move delay"}
    %f = idr.big.add %g, %g {expect.facts = "move delay"}
    %p = idr.big.pred %nat {expect.facts = "move delay"}
    %q = idr.big.pred %nat {expect.facts = "move delay"}
    return %a, %b, %c, %d, %e, %f, %p, %q
        : !idr.box<!L>, !idr.box<!L>, !idr.str, !idr.str, !idr.big, !idr.big, !idr.nat, !idr.nat
  }
  idr.func @dead(%x: i64, %l: !idr.box<!L>, %s: !idr.str, %g: !idr.big, %c: i32, %nat: !idr.nat) {
    %a = idr.con !idr.box<!L> @Cons(%x : i64, %l : !idr.box<!L>)
    %b = idr.str.append %s, %s
    %d = idr.str.cons %c, %s
    %e = idr.str.from_char %c
    %f = idr.str.show signed %x : i64
    %h = idr.str.substr %s, %x, %x
    %i = idr.str.reverse %s
    %j = idr.big.mul %g, %g
    %k = idr.big.neg %g
    %z = idr.big.pred %nat
    %m = idr.big.from_int signed %x : i64
    %n = idr.big.show %g
    %o = idr.big.from_str %s
    %p = idr.str.length %s
    %q = idr.str.cmp lt %s, %s
    %r = idr.big.cmp eq %g, %g
    %t = idr.big.to_int %g : i32
    %u = idr.big.to_double %g
    %v = idr.str.to_int signed %s : i64
    %w = idr.str.to_double %s
    %y = idr.int_head signed %x : i64
    return
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
