// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s
// rule: SEM-EVAL-5, LOW-TAIL-4
// LOW-TAIL-4: idr.may_loop keeps a loop that may not terminate, even when its
// results are unused; an effect-free loop without it is dead code.

// CHECK-LABEL: func.func @kept(
// CHECK: scf.while
// CHECK: idr.may_loop
func.func @kept(%n: i64) {
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

// CHECK-LABEL: func.func @removed(
// CHECK-NEXT: return
func.func @removed(%n: i64) {
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
