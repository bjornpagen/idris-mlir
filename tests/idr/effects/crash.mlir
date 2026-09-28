// RUN: idris-mlir-opt %s --canonicalize --cse | FileCheck %s
// Every op that may crash keeps its crash when its result is unused, and
// loses it exactly when the operands rule the crash out (the crash also
// writes the IO resource, so it stays ordered with output).

// CHECK-LABEL: func.func @may_crash(
// CHECK-SAME: %[[S:.*]]: !idr.str, %[[I:.*]]: i64, %[[B:.*]]: !idr.big, %[[D:.*]]: f64)
// CHECK-NEXT: idr.str.index %[[S]], %[[I]]
// CHECK-NEXT: idr.str.head %[[S]]
// CHECK-NEXT: idr.str.tail %[[S]]
// CHECK-NEXT: idr.big.div %[[B]], %[[B]]
// CHECK-NEXT: idr.big.mod %[[B]], %[[B]]
// CHECK-NEXT: idr.big.from_double %[[D]]
// CHECK-NEXT: idr.to_int %[[D]] : i64
// CHECK-NEXT: return
func.func @may_crash(%s: !idr.str, %i: i64, %b: !idr.big, %d: f64) {
  %0 = idr.str.index %s, %i
  %1 = idr.str.head %s
  %2 = idr.str.tail %s
  %3 = idr.big.div %b, %b
  %4 = idr.big.mod %b, %b
  %5 = idr.big.from_double %d
  %6 = idr.to_int %d : i64
  return
}

// The same ops on operands that rule out the crash are dead code.
// CHECK-LABEL: func.func @cannot_crash(
// CHECK-NEXT: return
func.func @cannot_crash(%s: !idr.str, %c: i32, %x: i64, %b: !idr.big) {
  %lit = idr.constant "h\C3\A9!" : !idr.str
  %two = arith.constant 2 : i64
  %0 = idr.str.index %lit, %two
  %cons = idr.str.cons %c, %s
  %1 = idr.str.head %cons
  %2 = idr.str.tail %lit
  %shown = idr.str.show signed %x : i64
  %3 = idr.str.tail %shown
  %appended = idr.str.append %s, %lit
  %4 = idr.str.head %appended
  %seven = idr.constant #idr.big<"-7"> : !idr.big
  %5 = idr.big.div %b, %seven
  %6 = idr.big.mod %b, %seven
  %half = arith.constant 0.5 : f64
  %7 = idr.big.from_double %half
  %8 = idr.to_int %half : i64
  return
}

// An index past the last character (not the last byte) may crash.
// CHECK-LABEL: func.func @past_end(
// CHECK: idr.str.index
func.func @past_end() {
  %lit = idr.constant "h\C3\A9!" : !idr.str
  %three = arith.constant 3 : i64
  %0 = idr.str.index %lit, %three
  return
}

// A crash is kept, and two are not merged.
// CHECK-LABEL: func.func @crash(
// CHECK: idr.crash "a"
// CHECK-NEXT: ub.unreachable
func.func @crash() {
  idr.crash "a"
  ub.unreachable
}
