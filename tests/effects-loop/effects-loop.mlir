// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=loops=@kept:1,loops=@removed:0,loops=@used:1 -o /dev/null
// idr.may_loop keeps a loop that may not terminate, even when its
// results are unused; an effect-free loop without it is dead code, and
// only when unused: the same loop whose result is returned stays.

idr.program @loop root(@root) stage(first) {
  idr.func @kept(%n: i64) {
    %r = scf.while (%i = %n) : (i64) -> i64 {
      idr.may_loop
      %c = arith.constant 0 : i64
      %go = arith.cmpi ne, %i, %c : i64
      scf.condition(%go) %i : i64
    } do {
    ^bb0(%j: i64):
      scf.yield %j : i64
    }
    return
  }

  idr.func @removed(%n: i64) {
    %r = scf.while (%i = %n) : (i64) -> i64 {
      %c = arith.constant 0 : i64
      %go = arith.cmpi ne, %i, %c : i64
      scf.condition(%go) %i : i64
    } do {
    ^bb0(%j: i64):
      scf.yield %j : i64
    }
    return
  }
  idr.func @used(%n: i64) -> i64 {
    %r = scf.while (%i = %n) : (i64) -> i64 {
      %c = arith.constant 0 : i64
      %go = arith.cmpi ne, %i, %c : i64
      scf.condition(%go) %i : i64
    } do {
    ^bb0(%j: i64):
      %one = arith.constant 1 : i64
      %k = arith.subi %j, %one : i64
      scf.yield %k : i64
    }
    return %r : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
