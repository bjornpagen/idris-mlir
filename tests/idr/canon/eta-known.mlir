// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s
// RUN: idris-mlir-opt %s --canonicalize=test-convergence=true -o /dev/null
// Record eta knows the constructor from the match that took the value
// apart, and from a type of one constructor; rebuilt in another
// constructor's case, from two values, or with its fields swapped, a
// constructor stays.


// In the case that matched it, a value rebuilt from the case's reads of it
// is the value; with the fields swapped it is a new one.
// CHECK-LABEL: idr.func private @in_case(
// CHECK-SAME: %[[P:.*]]: !Pair)
// CHECK: {{(idr\.)?}}match %[[P]]
// CHECK: case @Left(
// CHECK-NOT: {{(idr\.| )con }}
// CHECK: idr.yield %[[P]]
// CHECK: case @Right(%[[A:.*]]: i64, %[[B:.*]]: i64)
// CHECK: %[[S:.*]] = {{(idr\.)?}}con @Left(%[[B]], %[[A]])
// CHECK: idr.yield %[[S]]
!Pair = !idr.data<"Pair", plain [@Left(i64, i64), @Right(i64, i64)]>
!One = !idr.data<"One", plain [@Only(i64)]>
idr.func private @in_case(%p: !Pair) -> !Pair {
  %r = idr.match %p : !Pair -> (!Pair) {
  case @Left(%a: i64, %b: i64) {
    %x = idr.field %p[@Left, 0] : !Pair -> i64
    %y = idr.field %p[@Left, 1] : !Pair -> i64
    %c = idr.con @Left(%x, %y) : (i64, i64) -> !Pair
    idr.yield %c : !Pair
  }
  case @Right(%a: i64, %b: i64) {
    %c = idr.con @Left(%b, %a) : (i64, i64) -> !Pair
    idr.yield %c : !Pair
  }
  }
  return %r : !Pair
}

// In the other constructor's case the value is not known to be what the
// rebuild builds, and the type has another constructor: it stays.
// CHECK-LABEL: idr.func private @wrong_case(
// CHECK-SAME: %[[P:.*]]: !Pair)
// CHECK: case @Right(
// CHECK-DAG: %{{.*}} = {{(idr\.)?}}field %[[P]][@Left, 0]
// CHECK-DAG: %{{.*}} = {{(idr\.)?}}field %[[P]][@Left, 1]
// CHECK: %[[C:.*]] = {{(idr\.)?}}con @Left(
// CHECK: idr.yield %[[C]]
idr.func private @wrong_case(%p: !Pair) -> !Pair {
  %r = idr.match %p : !Pair -> (!Pair) {
  case @Left(%a: i64, %b: i64) {
    idr.yield %p : !Pair
  }
  case @Right(%a: i64, %b: i64) {
    %x = idr.field %p[@Left, 0] : !Pair -> i64
    %y = idr.field %p[@Left, 1] : !Pair -> i64
    %c = idr.con @Left(%x, %y) : (i64, i64) -> !Pair
    idr.yield %c : !Pair
  }
  }
  return %r : !Pair
}

// A type of one constructor needs no match: the value is that constructor.
// CHECK-LABEL: idr.func private @singleton(
// CHECK-SAME: %[[O:.*]]: !One)
// CHECK-NOT: {{(idr\.| )con }}
// CHECK: return %[[O]]
idr.func private @singleton(%o: !One) -> !One {
  %f = idr.field %o[@Only, 0] : !One -> i64
  %c = idr.con @Only(%f) : (i64) -> !One
  return %c : !One
}

// Fields read from two values rebuild neither.
// CHECK-LABEL: idr.func private @two_sources(
// CHECK: %[[C:.*]] = {{(idr\.)?}}con @Left(
// CHECK: return %[[C]]
idr.func private @two_sources(%p: !Pair, %q: !Pair) -> !Pair {
  %x = idr.field %p[@Left, 0] : !Pair -> i64
  %y = idr.field %q[@Left, 1] : !Pair -> i64
  %c = idr.con @Left(%x, %y) : (i64, i64) -> !Pair
  return %c : !Pair
}
