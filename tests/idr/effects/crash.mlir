// RUN: idris-mlir-opt %s --canonicalize --cse | FileCheck %s
// A primitive that may crash is its guard and the op it guards, as Emit
// writes it. When its result is unused the op goes, since it only
// computes, and the guard keeps its crash; the guard goes exactly when its
// operands rule the crash out. A crash also writes the IO resource, so it
// stays ordered with output, and two guards are not merged.

// CHECK-LABEL: func.func @may_crash(
// CHECK-SAME: %[[S:.*]]: !idr.str, %[[I:.*]]: i64, %[[B:.*]]: !idr.big, %[[D:.*]]: f64)
// CHECK-NEXT: %[[N:.*]] = idr.str.length %[[S]]
// CHECK-NEXT: idr.check.in_bounds %[[I]], %[[N]], "string index out of range"
// CHECK-NEXT: idr.check.nonempty %[[S]], "head of an empty string" : !idr.str
// CHECK-NEXT: idr.check.nonempty %[[S]], "tail of an empty string" : !idr.str
// CHECK-NEXT: idr.check.nonzero %[[B]], "division by zero" : !idr.big
// CHECK-NEXT: idr.check.nonzero %[[B]], "division by zero" : !idr.big
// CHECK-NEXT: idr.check.finite %[[D]], "cast of a non-finite Double"
// CHECK-NEXT: idr.check.finite %[[D]], "cast of a non-finite Double"
// CHECK-NEXT: return
func.func @may_crash(%s: !idr.str, %i: i64, %b: !idr.big, %d: f64) {
  %n = idr.str.length %s
  %i0 = idr.check.in_bounds %i, %n, "string index out of range"
  %0 = idr.str.index %s, %i0
  %s1 = idr.check.nonempty %s, "head of an empty string" : !idr.str
  %1 = idr.str.head %s1
  %s2 = idr.check.nonempty %s, "tail of an empty string" : !idr.str
  %2 = idr.str.tail %s2
  %b3 = idr.check.nonzero %b, "division by zero" : !idr.big
  %3 = idr.big.div %b, %b3
  %b4 = idr.check.nonzero %b, "division by zero" : !idr.big
  %4 = idr.big.mod %b, %b4
  %d5 = idr.check.finite %d, "cast of a non-finite Double"
  %5 = idr.big.from_double %d5
  %d6 = idr.check.finite %d, "cast of a non-finite Double"
  %6 = idr.to_int %d6 : i64
  return
}

// The same primitives on operands that rule out the crash are dead code,
// guards and all.
// CHECK-LABEL: func.func @cannot_crash(
// CHECK-NEXT: return
func.func @cannot_crash(%s: !idr.str, %c: i32, %x: i64, %b: !idr.big) {
  %lit = idr.constant "h\C3\A9!" : !idr.str
  %two = arith.constant 2 : i64
  %n = idr.str.length %lit
  %i0 = idr.check.in_bounds %two, %n, "string index out of range"
  %0 = idr.str.index %lit, %i0
  %cons = idr.str.cons %c, %s
  %s1 = idr.check.nonempty %cons, "head of an empty string" : !idr.str
  %1 = idr.str.head %s1
  %s2 = idr.check.nonempty %lit, "tail of an empty string" : !idr.str
  %2 = idr.str.tail %s2
  %shown = idr.str.show signed %x : i64
  %s3 = idr.check.nonempty %shown, "tail of an empty string" : !idr.str
  %3 = idr.str.tail %s3
  %appended = idr.str.append %s, %lit
  %s4 = idr.check.nonempty %appended, "head of an empty string" : !idr.str
  %4 = idr.str.head %s4
  %seven = idr.constant #idr.big<"-7"> : !idr.big
  %b5 = idr.check.nonzero %seven, "division by zero" : !idr.big
  %5 = idr.big.div %b, %b5
  %b6 = idr.check.nonzero %seven, "division by zero" : !idr.big
  %6 = idr.big.mod %b, %b6
  %half = arith.constant 0.5 : f64
  %d7 = idr.check.finite %half, "cast of a non-finite Double"
  %7 = idr.big.from_double %d7
  %d8 = idr.check.finite %half, "cast of a non-finite Double"
  %8 = idr.to_int %d8 : i64
  return
}

// An index past the last character (not the last byte) may crash.
// CHECK-LABEL: func.func @past_end(
// CHECK: idr.check.in_bounds
func.func @past_end() {
  %lit = idr.constant "h\C3\A9!" : !idr.str
  %three = arith.constant 3 : i64
  %n = idr.str.length %lit
  %i0 = idr.check.in_bounds %three, %n, "string index out of range"
  %0 = idr.str.index %lit, %i0
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
