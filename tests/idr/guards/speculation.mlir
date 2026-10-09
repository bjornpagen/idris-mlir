// RUN: idris-mlir-opt %s --loop-invariant-code-motion | FileCheck %s
// A total op that only computes runs anywhere its operands are good: past
// the guard of its own string's length, or on a constant its guard would
// let through. Where a proof removed the guard, what made the index good is
// the path to the op, so the op stays on that path. In each loop below the
// string and the index are invariant, and the read is at the top of the
// loop's body, which runs only while the index is below the length.
// @proved's guard is gone, proved by the loop's condition: the read stays in
// the loop. @guarded's index is the result of a guard against the length of
// the string it reads: the read may run anywhere, and leaves the loop.
// @other's index went through a guard against another string's length,
// which says nothing of this one: the read stays.
// CHECK-LABEL: func.func @proved(
// CHECK: scf.while
// CHECK: } do {
// CHECK: idr.str.index
// CHECK: scf.yield
// CHECK-LABEL: func.func @guarded(
// CHECK: idr.str.index
// CHECK: scf.while
// CHECK-NOT: idr.str.index
// CHECK: return
// CHECK-LABEL: func.func @other(
// CHECK: scf.while
// CHECK: } do {
// CHECK: idr.str.index
// CHECK: scf.yield
func.func @proved(%s: !idr.str, %i: i64, %n: i64) -> i32 {
  %zero = arith.constant 0 : i32
  %none = arith.constant 0 : i64
  %one = arith.constant 1 : i64
  %r:2 = scf.while (%k = %n, %acc = %zero) : (i64, i32) -> (i64, i32) {
    %len = idr.str.length %s
    %low = arith.cmpi sge, %i, %none : i64
    %below = arith.cmpi slt, %i, %len : i64
    %more = arith.cmpi sgt, %k, %none : i64
    %in = arith.andi %low, %below : i1
    %go = arith.andi %in, %more : i1
    scf.condition(%go) %k, %acc : i64, i32
  } do {
  ^bb0(%k: i64, %acc: i32):
    %c = idr.str.index %s, %i
    %a = arith.addi %acc, %c : i32
    %k1 = arith.subi %k, %one : i64
    scf.yield %k1, %a : i64, i32
  }
  return %r#1 : i32
}

func.func @guarded(%s: !idr.str, %i: i64, %n: i64) -> i32 {
  %zero = arith.constant 0 : i32
  %none = arith.constant 0 : i64
  %one = arith.constant 1 : i64
  %len = idr.str.length %s
  %g = idr.check.in_bounds %i, %len, "string index out of range"
  %r:2 = scf.while (%k = %n, %acc = %zero) : (i64, i32) -> (i64, i32) {
    %more = arith.cmpi sgt, %k, %none : i64
    scf.condition(%more) %k, %acc : i64, i32
  } do {
  ^bb0(%k: i64, %acc: i32):
    %c = idr.str.index %s, %g
    %a = arith.addi %acc, %c : i32
    %k1 = arith.subi %k, %one : i64
    scf.yield %k1, %a : i64, i32
  }
  return %r#1 : i32
}

func.func @other(%s: !idr.str, %t: !idr.str, %i: i64, %n: i64) -> i32 {
  %zero = arith.constant 0 : i32
  %none = arith.constant 0 : i64
  %one = arith.constant 1 : i64
  %len = idr.str.length %t
  %g = idr.check.in_bounds %i, %len, "string index out of range"
  %r:2 = scf.while (%k = %n, %acc = %zero) : (i64, i32) -> (i64, i32) {
    %more = arith.cmpi sgt, %k, %none : i64
    scf.condition(%more) %k, %acc : i64, i32
  } do {
  ^bb0(%k: i64, %acc: i32):
    %c = idr.str.index %s, %g
    %a = arith.addi %acc, %c : i32
    %k1 = arith.subi %k, %one : i64
    scf.yield %k1, %a : i64, i32
  }
  return %r#1 : i32
}
