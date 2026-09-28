// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s
// RUN: idris-mlir-opt %s --canonicalize --inline | FileCheck %s --check-prefix=INLINE
// rule: IDR-CLOS-1, ELIM-G-1, ELIM-G-8
// Applying a known closure calls its function with the captures first, as
// upstream's func.call_indirect of a constant becomes a direct call; the
// inliner then removes the call.

func.func private @add(%a: i64, %b: i64) -> i64 {
  %r = arith.addi %a, %b : i64
  return %r : i64
}
func.func private @delayed(%a: i64) -> i64 {
  %r = arith.muli %a, %a : i64
  return %r : i64
}
idr.data @S {
  idr.ctor @MkS tag 0 (i64, !idr.str) {quantities = ["w", "w"]}
}
func.func private @pick(%s: !idr.data<@S>, %t: !idr.str, %n: i64) -> i64 {
  return %n : i64
}

// CHECK-LABEL: func.func @of_closure(
// CHECK-SAME: %[[X:.*]]: i64, %[[Y:.*]]: i64)
// CHECK-NEXT: %[[R:.*]] = call @add(%[[X]], %[[Y]]) : (i64, i64) -> i64
// CHECK-NEXT: return %[[R]]
// INLINE-LABEL: func.func @of_closure(
// INLINE-NEXT: arith.addi
func.func @of_closure(%x: i64, %y: i64) -> i64 {
  %c = idr.closure @add(%x) : (i64) -> !idr.fn<(i64) -> (i64)>
  %r = idr.apply %c(%y) : !idr.fn<(i64) -> (i64)>
  return %r : i64
}

// A constant closure's captures become constants.
// CHECK-LABEL: func.func @of_constant(
// CHECK-SAME: %[[Y:.*]]: i64)
// CHECK: %[[C:.*]] = arith.constant 5 : i64
// CHECK: %[[R:.*]] = call @add(%[[C]], %[[Y]]) : (i64, i64) -> i64
// CHECK-NEXT: return %[[R]]
func.func @of_constant(%y: i64) -> i64 {
  %c = idr.constant #idr.closure<@add, [5 : i64]> : !idr.fn<(i64) -> (i64)>
  %r = idr.apply %c(%y) : !idr.fn<(i64) -> (i64)>
  return %r : i64
}

// Captures of every kind of constant.
// CHECK-LABEL: func.func @of_constant_data(
// CHECK-DAG: %[[S:.*]] = idr.constant #idr.con<@S::@MkS, [1, "a"]> : !idr.data<@S>
// CHECK-DAG: %[[T:.*]] = idr.constant "b" : !idr.str
// CHECK: call @pick(%[[S]], %[[T]], %{{.*}})
func.func @of_constant_data(%n: i64) -> i64 {
  %c = idr.constant #idr.closure<@pick, [#idr.con<@S::@MkS, [1 : i64, "a"]>, "b"]>
     : !idr.fn<(i64) -> (i64)>
  %r = idr.apply %c(%n) : !idr.fn<(i64) -> (i64)>
  return %r : i64
}

// Forcing a delayed value (a closure of no arguments).
// CHECK-LABEL: func.func @force(
// CHECK-SAME: %[[X:.*]]: i64)
// CHECK-NEXT: %[[R:.*]] = call @delayed(%[[X]]) : (i64) -> i64
// CHECK-NEXT: return %[[R]]
func.func @force(%x: i64) -> i64 {
  %d = idr.closure @delayed(%x) : (i64) -> !idr.fn<() -> (i64)>
  %r = idr.apply %d() : !idr.fn<() -> (i64)>
  return %r : i64
}

// An unknown closure stays applied.
// CHECK-LABEL: func.func @unknown(
// CHECK: idr.apply
func.func @unknown(%c: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 {
  %r = idr.apply %c(%x) : !idr.fn<(i64) -> (i64)>
  return %r : i64
}
