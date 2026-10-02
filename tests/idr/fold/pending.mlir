// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s
// A field a constructor was built without (idr.dest.pending, the
// destination idr-trmc writes after the constructor is built) has no value
// until it is written, so a read of it is never the pending operand,
// however the field is read: directly, through a match whose taken region
// is known, or at another grade. The read stays a read of the cell; the
// fields the constructor was built with fold as ever.

idr.data @List box {
  idr.ctor @Nil ()
  idr.ctor @Cons (i64, !idr.box<@List>)
}
idr.data @LList box {
  idr.ctor @LNil ()
  idr.ctor @LCons (i64, !idr.lin<!idr.box<@LList>>)
}

// CHECK-LABEL: func.func @direct(
// CHECK-SAME: %[[X:[^:]*]]: i64
// CHECK: %[[C:.*]] = idr.con @List::@Cons(%[[X]], %{{.*}})
// CHECK: %[[T:.*]] = idr.field %[[C]][@Cons, 1]
// CHECK: return %[[X]], %[[T]]
func.func @direct(%x: i64) -> (i64, !idr.box<@List>) {
  %p = idr.dest.pending : !idr.box<@List>
  %c = idr.con @List::@Cons(%x, %p) : (i64, !idr.box<@List>) -> !idr.box<@List>
  %h = idr.field %c[@Cons, 0] : !idr.box<@List> -> i64
  %t = idr.field %c[@Cons, 1] : !idr.box<@List> -> !idr.box<@List>
  return %h, %t : i64, !idr.box<@List>
}

// The match's taken region is known, so the region replaces it and its
// arguments become reads of the constructor's fields.
// CHECK-LABEL: func.func @through_match(
// CHECK-SAME: %[[X:[^:]*]]: i64
// CHECK: %[[C:.*]] = idr.con @List::@Cons(%[[X]], %{{.*}})
// CHECK: %[[T:.*]] = idr.field %[[C]][@Cons, 1]
// CHECK-NOT: idr.match
// CHECK: return %[[X]], %[[T]]
func.func @through_match(%x: i64) -> (i64, !idr.box<@List>) {
  %p = idr.dest.pending : !idr.box<@List>
  %c = idr.con @List::@Cons(%x, %p) : (i64, !idr.box<@List>) -> !idr.box<@List>
  %r:2 = idr.match %c : !idr.box<@List> -> (i64, !idr.box<@List>) {
  case @Nil() {
    %zero = arith.constant 0 : i64
    %nil = idr.constant #idr.con<@List::@Nil, []> : !idr.box<@List>
    idr.yield %zero, %nil : i64, !idr.box<@List>
  }
  case @Cons(%h: i64, %t: !idr.box<@List>) {
    idr.yield %h, %t : i64, !idr.box<@List>
  }
  }
  return %r#0, %r#1 : i64, !idr.box<@List>
}

// A linear field read once moves out of the constructor into its read,
// used out of its grade; a pending one has nothing to move.
// CHECK-LABEL: func.func @at_grade(
// CHECK-SAME: %[[X:[^:]*]]: i64
// CHECK: %[[C:.*]] = idr.con @LList::@LCons(%[[X]], %{{.*}})
// CHECK: %[[T:.*]] = idr.field %[[C]][@LCons, 1]
// CHECK: return %[[T]]
func.func @at_grade(%x: i64) -> !idr.box<@LList> {
  %p = idr.dest.pending : !idr.lin<!idr.box<@LList>>
  %c = idr.con @LList::@LCons(%x, %p) : (i64, !idr.lin<!idr.box<@LList>>) -> !idr.box<@LList>
  %t = idr.field %c[@LCons, 1] : !idr.box<@LList> -> !idr.box<@LList>
  return %t : !idr.box<@LList>
}
