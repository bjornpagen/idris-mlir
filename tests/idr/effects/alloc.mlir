// RUN: idris-mlir-opt %s --cse --canonicalize | FileCheck %s
// rule: IDR-CON-1, IDR-STR-2, IDR-BIG-1, ELIM-G-9
// Ops that allocate their result (a box's idr.con, string builders, big
// ops) are never merged, so that no two cells become one, but an unused one
// is dead code. An unboxed constructor is Pure: equal ones merge.

idr.data @P {
  idr.ctor @MkP tag 0 (i64, i64) {quantities = ["w", "w"]}
}
idr.data @L box {
  idr.ctor @Nil tag 0 () {quantities = []}
  idr.ctor @Cons tag 1 (i64, !idr.box<@L>) {quantities = ["w", "w"]}
}

// CHECK-LABEL: func.func @merged(
// CHECK: %[[P:.*]] = idr.con @P::@MkP
// CHECK-NOT: idr.con
// CHECK: return %[[P]], %[[P]]
func.func @merged(%x: i64) -> (!idr.data<@P>, !idr.data<@P>) {
  %a = idr.con @P::@MkP(%x, %x) : (i64, i64) -> !idr.data<@P>
  %b = idr.con @P::@MkP(%x, %x) : (i64, i64) -> !idr.data<@P>
  return %a, %b : !idr.data<@P>, !idr.data<@P>
}

// CHECK-LABEL: func.func @cells(
// CHECK: %[[A:.*]] = idr.con @L::@Cons
// CHECK: %[[B:.*]] = idr.con @L::@Cons
// CHECK: %[[S:.*]] = idr.str.append
// CHECK: %[[T:.*]] = idr.str.append
// CHECK: %[[G:.*]] = idr.big.add
// CHECK: %[[H:.*]] = idr.big.add
// CHECK: return %[[A]], %[[B]], %[[S]], %[[T]], %[[G]], %[[H]]
func.func @cells(%x: i64, %l: !idr.box<@L>, %s: !idr.str, %g: !idr.big)
    -> (!idr.box<@L>, !idr.box<@L>, !idr.str, !idr.str, !idr.big, !idr.big) {
  %a = idr.con @L::@Cons(%x, %l) : (i64, !idr.box<@L>) -> !idr.box<@L>
  %b = idr.con @L::@Cons(%x, %l) : (i64, !idr.box<@L>) -> !idr.box<@L>
  %c = idr.str.append %s, %s
  %d = idr.str.append %s, %s
  %e = idr.big.add %g, %g
  %f = idr.big.add %g, %g
  return %a, %b, %c, %d, %e, %f : !idr.box<@L>, !idr.box<@L>, !idr.str, !idr.str, !idr.big, !idr.big
}

// CHECK-LABEL: func.func @dead(
// CHECK-NEXT: return
func.func @dead(%x: i64, %l: !idr.box<@L>, %s: !idr.str, %g: !idr.big, %c: i32) {
  %a = idr.con @L::@Cons(%x, %l) : (i64, !idr.box<@L>) -> !idr.box<@L>
  %b = idr.str.append %s, %s
  %d = idr.str.cons %c, %s
  %e = idr.str.from_char %c
  %f = idr.str.show signed %x : i64
  %h = idr.str.substr %s, %x, %x
  %i = idr.str.reverse %s
  %j = idr.big.mul %g, %g
  %k = idr.big.neg %g
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
