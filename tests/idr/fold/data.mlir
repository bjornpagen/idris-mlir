// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s
// Constructors of constants fold to constants; fields and tags of known
// constructors fold.

idr.data @S {
  idr.ctor @A tag 0 () {quantities = []}
  idr.ctor @B tag 1 (i64, !idr.str) {quantities = ["w", "w"]}
}
idr.data @One {
  idr.ctor @Only tag 0 (i64) {quantities = ["w"]}
}
idr.data @L box {
  idr.ctor @Nil tag 0 () {quantities = []}
  idr.ctor @Cons tag 1 (i64, !idr.box<@L>) {quantities = ["w", "w"]}
}

// CHECK-LABEL: func.func @constant_con
// CHECK-DAG: %[[S:.*]] = idr.constant #idr.con<@S::@B, [1, "x"]> : !idr.data<@S>
// CHECK-DAG: %[[L:.*]] = idr.constant #idr.con<@L::@Cons, [2, #idr.con<@L::@Nil, []>]> : !idr.box<@L>
// CHECK-NOT: idr.con
// CHECK: return %[[S]], %[[L]]
func.func @constant_con() -> (!idr.data<@S>, !idr.box<@L>) {
  %one = arith.constant 1 : i64
  %two = arith.constant 2 : i64
  %x = idr.constant "x" : !idr.str
  %s = idr.con @S::@B(%one, %x) : (i64, !idr.str) -> !idr.data<@S>
  %nil = idr.con @L::@Nil() : () -> !idr.box<@L>
  %l = idr.con @L::@Cons(%two, %nil) : (i64, !idr.box<@L>) -> !idr.box<@L>
  return %s, %l : !idr.data<@S>, !idr.box<@L>
}

// A constructor with a runtime field stays; its fields and tag fold.
// CHECK-LABEL: func.func @known(
// CHECK-SAME: %[[X:.*]]: i64)
// CHECK-DAG: %[[ONE:.*]] = arith.constant 1 : i64
// CHECK-DAG: %[[Y:.*]] = idr.constant "y" : !idr.str
// CHECK-NOT: idr.field
// CHECK-NOT: idr.tag
// CHECK: return %[[ONE]], %[[X]], %[[Y]]
func.func @known(%x: i64) -> (i64, i64, !idr.str) {
  %y = idr.constant "y" : !idr.str
  %s = idr.con @S::@B(%x, %y) : (i64, !idr.str) -> !idr.data<@S>
  %t = idr.tag %s : !idr.data<@S>
  %f = idr.field %s[@B, 0] : !idr.data<@S> -> i64
  %g = idr.field %s[@B, 1] : !idr.data<@S> -> !idr.str
  return %t, %f, %g : i64, i64, !idr.str
}

// Fields and tags of a constant fold, nested ones included.
// CHECK-LABEL: func.func @of_constant
// CHECK-DAG: %[[SEVEN:.*]] = arith.constant 7 : i64
// CHECK-DAG: %[[ONE:.*]] = arith.constant 1 : i64
// CHECK-DAG: %[[NIL:.*]] = idr.constant #idr.con<@L::@Nil, []> : !idr.box<@L>
// CHECK: return %[[SEVEN]], %[[ONE]], %[[NIL]]
func.func @of_constant() -> (i64, i64, !idr.box<@L>) {
  %l = idr.constant #idr.con<@L::@Cons, [7 : i64, #idr.con<@L::@Nil, []>]> : !idr.box<@L>
  %h = idr.field %l[@Cons, 0] : !idr.box<@L> -> i64
  %t = idr.tag %l : !idr.box<@L>
  %n = idr.field %l[@Cons, 1] : !idr.box<@L> -> !idr.box<@L>
  return %h, %t, %n : i64, i64, !idr.box<@L>
}

// A field of another constructor is unspecified and does not fold; the tag
// of a type of one constructor is 0.
// CHECK-LABEL: func.func @unknown(
// CHECK-SAME: %[[V:.*]]: !idr.data<@S>, %[[O:.*]]: !idr.data<@One>)
// CHECK-DAG: %[[ZERO:.*]] = arith.constant 0 : i64
// CHECK-DAG: %[[F:.*]] = idr.field %{{.*}}[@B, 0] : !idr.data<@S> -> i64
// CHECK-DAG: %[[T:.*]] = idr.tag %[[V]] : !idr.data<@S>
// CHECK: return %[[F]], %[[T]], %[[ZERO]]
func.func @unknown(%v: !idr.data<@S>, %o: !idr.data<@One>) -> (i64, i64, i64) {
  %a = idr.con @S::@A() : () -> !idr.data<@S>
  %f = idr.field %a[@B, 0] : !idr.data<@S> -> i64
  %t = idr.tag %v : !idr.data<@S>
  %u = idr.tag %o : !idr.data<@One>
  return %f, %t, %u : i64, i64, i64
}

// Equal constants are one value.
// CHECK-LABEL: func.func @cse
// CHECK: %[[C:.*]] = idr.constant #idr.big<"12345678901234567890"> : !idr.big
// CHECK-NOT: idr.constant
// CHECK: return %[[C]], %[[C]]
func.func @cse() -> (!idr.big, !idr.big) {
  %a = idr.constant #idr.big<"12345678901234567890"> : !idr.big
  %b = idr.constant #idr.big<"12345678901234567890"> : !idr.big
  return %a, %b : !idr.big, !idr.big
}
