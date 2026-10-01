// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s
// A match whose cases name every constructor cannot take its default
// region, so the region goes: Idris's case trees carry one for the clauses
// after a complete split, and it would look like a path to every analysis.
// A match with a constructor left over keeps its default.
// CHECK-LABEL: func.func private @covered(
// CHECK: idr.match %{{.*}} : !idr.data<@Q> -> (i64) {
// CHECK: case @A(
// CHECK: case @B(
// CHECK-NOT: default
// CHECK-LABEL: func.func private @open(
// CHECK: default {
module attributes {idr.program} {
  idr.data @Q {
    idr.ctor @A (i64)
    idr.ctor @B ()
  }
  func.func private @covered(%q: !idr.data<@Q>) -> i64 {
    %r = idr.match %q : !idr.data<@Q> -> (i64) {
    case @A(%x: i64) {
      idr.yield %x : i64
    }
    case @B() {
      %one = arith.constant 1 : i64
      idr.yield %one : i64
    }
    default {
      %two = arith.constant 2 : i64
      idr.yield %two : i64
    }
    }
    return %r : i64
  }
  func.func private @open(%q: !idr.data<@Q>) -> i64 {
    %r = idr.match %q : !idr.data<@Q> -> (i64) {
    case @A(%x: i64) {
      idr.yield %x : i64
    }
    default {
      %two = arith.constant 2 : i64
      idr.yield %two : i64
    }
    }
    return %r : i64
  }
  func.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}
