// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s
// Constructors of constants fold to constants; fields and tags of known
// constructors fold.


// CHECK-LABEL: idr.func private @constant_con
// CHECK-DAG: %[[S:.*]] = {{(idr\.)?}}constant #idr.con<@B, [1, "x"]> : !S
// CHECK-DAG: %[[L:.*]] = {{(idr\.)?}}constant #idr.con<@Cons, [2, #idr.con<@Nil, []>]> : !idr.box<!L>
// CHECK-NOT: {{(idr\.| )con }}
// CHECK: return %[[S]], %[[L]]
!S = !idr.data<"S", plain [@A(), @B(i64, !idr.str)]>
!One = !idr.data<"One", plain [@Only(i64)]>
!L = !idr.data<"L", list [@Nil(), @Cons(i64, !idr.box<!idr.data<"L">>)]>
idr.func private @constant_con() -> (!S, !idr.box<!L>) {
  %one = arith.constant 1 : i64
  %two = arith.constant 2 : i64
  %x = idr.constant "x" : !idr.str
  %s = idr.con @B(%one, %x) : (i64, !idr.str) -> !S
  %nil = idr.con @Nil() : () -> !idr.box<!L>
  %l = idr.con @Cons(%two, %nil) : (i64, !idr.box<!L>) -> !idr.box<!L>
  return %s, %l : !S, !idr.box<!L>
}

// A constructor with a runtime field stays; its fields and tag fold.
// CHECK-LABEL: idr.func private @known(
// CHECK-SAME: %[[X:.*]]: i64)
// CHECK-DAG: %[[ONE:.*]] = arith.constant 1 : i64
// CHECK-DAG: %[[Y:.*]] = {{(idr\.)?}}constant "y" : !idr.str
// CHECK-NOT: {{(idr\.| )field }}
// CHECK-NOT: {{(idr\.| )tag }}
// CHECK: return %[[ONE]], %[[X]], %[[Y]]
idr.func private @known(%x: i64) -> (i64, i64, !idr.str) {
  %y = idr.constant "y" : !idr.str
  %s = idr.con @B(%x, %y) : (i64, !idr.str) -> !S
  %t = idr.tag %s : !S
  %f = idr.field %s[@B, 0] : !S -> i64
  %g = idr.field %s[@B, 1] : !S -> !idr.str
  return %t, %f, %g : i64, i64, !idr.str
}

// Fields and tags of a constant fold, nested ones included.
// CHECK-LABEL: idr.func private @of_constant
// CHECK-DAG: %[[SEVEN:.*]] = arith.constant 7 : i64
// CHECK-DAG: %[[ONE:.*]] = arith.constant 1 : i64
// CHECK-DAG: %[[NIL:.*]] = {{(idr\.)?}}constant #idr.con<@Nil, []> : !idr.box<!L>
// CHECK: return %[[SEVEN]], %[[ONE]], %[[NIL]]
idr.func private @of_constant() -> (i64, i64, !idr.box<!L>) {
  %l = idr.constant #idr.con<@Cons, [7 : i64, #idr.con<@Nil, []>]> : !idr.box<!L>
  %h = idr.field %l[@Cons, 0] : !idr.box<!L> -> i64
  %t = idr.tag %l : !idr.box<!L>
  %n = idr.field %l[@Cons, 1] : !idr.box<!L> -> !idr.box<!L>
  return %h, %t, %n : i64, i64, !idr.box<!L>
}

// A field of another constructor is unspecified and does not fold; the tag
// of a type of one constructor is 0.
// CHECK-LABEL: idr.func private @unknown(
// CHECK-SAME: %[[V:.*]]: !S, %[[O:.*]]: !One)
// CHECK-DAG: %[[ZERO:.*]] = arith.constant 0 : i64
// CHECK-DAG: %[[F:.*]] = {{(idr\.)?}}field %{{.*}}[@B, 0] : !S -> i64
// CHECK-DAG: %[[T:.*]] = {{(idr\.)?}}tag %[[V]] : !S
// CHECK: return %[[F]], %[[T]], %[[ZERO]]
idr.func private @unknown(%v: !S, %o: !One) -> (i64, i64, i64) {
  %a = idr.con @A() : () -> !S
  %f = idr.field %a[@B, 0] : !S -> i64
  %t = idr.tag %v : !S
  %u = idr.tag %o : !One
  return %f, %t, %u : i64, i64, i64
}

// Equal constants are one value.
// CHECK-LABEL: idr.func private @cse
// CHECK: %[[C:.*]] = {{(idr\.)?}}constant #idr.big<"12345678901234567890"> : !idr.big
// CHECK-NOT: {{(idr\.| )constant }}
// CHECK: return %[[C]], %[[C]]
idr.func private @cse() -> (!idr.big, !idr.big) {
  %a = idr.constant #idr.big<"12345678901234567890"> : !idr.big
  %b = idr.constant #idr.big<"12345678901234567890"> : !idr.big
  return %a, %b : !idr.big, !idr.big
}
