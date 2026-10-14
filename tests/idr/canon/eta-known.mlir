// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s
// RUN: idris-mlir-opt %s --canonicalize=test-convergence=true -o /dev/null
// Record eta knows the constructor from the match that took the value
// apart, and from a type of one constructor; rebuilt in another
// constructor's case, from two values, or with its fields swapped, a
// constructor stays.

idr.data @Pair {
  idr.ctor @Left (i64, i64)
  idr.ctor @Right (i64, i64)
}
idr.data @One {
  idr.ctor @Only (i64)
}

// In the case that matched it, a value rebuilt from the case's reads of it
// is the value; with the fields swapped it is a new one.
// CHECK-LABEL: idr.func @in_case(
// CHECK-SAME: %[[P:.*]]: !Pair)
// CHECK: {{(idr\.)?}}match %[[P]]
// CHECK: case @Left(
// CHECK-NOT: {{(idr\.| )con }}
// CHECK: idr.yield %[[P]]
// CHECK: case @Right(%[[A:.*]]: i64, %[[B:.*]]: i64)
// CHECK: %[[S:.*]] = {{(idr\.)?}}con @Pair::@Left(%[[B]], %[[A]])
// CHECK: idr.yield %[[S]]
idr.func @in_case(%p: !idr.data<@Pair>) -> !idr.data<@Pair> {
  %r = idr.match %p : !idr.data<@Pair> -> (!idr.data<@Pair>) {
  case @Left(%a: i64, %b: i64) {
    %x = idr.field %p[@Left, 0] : !idr.data<@Pair> -> i64
    %y = idr.field %p[@Left, 1] : !idr.data<@Pair> -> i64
    %c = idr.con @Pair::@Left(%x, %y) : (i64, i64) -> !idr.data<@Pair>
    idr.yield %c : !idr.data<@Pair>
  }
  case @Right(%a: i64, %b: i64) {
    %c = idr.con @Pair::@Left(%b, %a) : (i64, i64) -> !idr.data<@Pair>
    idr.yield %c : !idr.data<@Pair>
  }
  }
  return %r : !idr.data<@Pair>
}

// In the other constructor's case the value is not known to be what the
// rebuild builds, and the type has another constructor: it stays.
// CHECK-LABEL: idr.func @wrong_case(
// CHECK-SAME: %[[P:.*]]: !Pair)
// CHECK: case @Right(
// CHECK-DAG: %{{.*}} = {{(idr\.)?}}field %[[P]][@Left, 0]
// CHECK-DAG: %{{.*}} = {{(idr\.)?}}field %[[P]][@Left, 1]
// CHECK: %[[C:.*]] = {{(idr\.)?}}con @Pair::@Left(
// CHECK: idr.yield %[[C]]
idr.func @wrong_case(%p: !idr.data<@Pair>) -> !idr.data<@Pair> {
  %r = idr.match %p : !idr.data<@Pair> -> (!idr.data<@Pair>) {
  case @Left(%a: i64, %b: i64) {
    idr.yield %p : !idr.data<@Pair>
  }
  case @Right(%a: i64, %b: i64) {
    %x = idr.field %p[@Left, 0] : !idr.data<@Pair> -> i64
    %y = idr.field %p[@Left, 1] : !idr.data<@Pair> -> i64
    %c = idr.con @Pair::@Left(%x, %y) : (i64, i64) -> !idr.data<@Pair>
    idr.yield %c : !idr.data<@Pair>
  }
  }
  return %r : !idr.data<@Pair>
}

// A type of one constructor needs no match: the value is that constructor.
// CHECK-LABEL: idr.func @singleton(
// CHECK-SAME: %[[O:.*]]: !One)
// CHECK-NOT: {{(idr\.| )con }}
// CHECK: return %[[O]]
idr.func @singleton(%o: !idr.data<@One>) -> !idr.data<@One> {
  %f = idr.field %o[@Only, 0] : !idr.data<@One> -> i64
  %c = idr.con @One::@Only(%f) : (i64) -> !idr.data<@One>
  return %c : !idr.data<@One>
}

// Fields read from two values rebuild neither.
// CHECK-LABEL: idr.func @two_sources(
// CHECK: %[[C:.*]] = {{(idr\.)?}}con @Pair::@Left(
// CHECK: return %[[C]]
idr.func @two_sources(%p: !idr.data<@Pair>, %q: !idr.data<@Pair>) -> !idr.data<@Pair> {
  %x = idr.field %p[@Left, 0] : !idr.data<@Pair> -> i64
  %y = idr.field %q[@Left, 1] : !idr.data<@Pair> -> i64
  %c = idr.con @Pair::@Left(%x, %y) : (i64, i64) -> !idr.data<@Pair>
  return %c : !idr.data<@Pair>
}
