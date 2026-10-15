// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s
// idr.may_loop keeps a loop that may not terminate, even when its
// results are unused; an effect-free loop without it is dead code.

// CHECK-LABEL: idr.func private @kept(
// CHECK: scf.while
// CHECK: may_loop
idr.func private @kept(%n: i64) {
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

// CHECK-LABEL: idr.func private @removed(
// CHECK-NEXT: return
idr.func private @removed(%n: i64) {
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
