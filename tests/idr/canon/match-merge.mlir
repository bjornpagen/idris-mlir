// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s
// rule: IDR-MATCH-5, IDR-MATCH-6
// Identical regions merge: a case that does what the default does goes to
// the default, and without a default, cases that do the same become it.

idr.data @C {
  idr.ctor @R tag 0 () {quantities = []}
  idr.ctor @G tag 1 (i64) {quantities = ["w"]}
  idr.ctor @B tag 2 () {quantities = []}
}

// CHECK-LABEL: func.func @into_default(
// CHECK: idr.match_lit %{{.*}} : i64 -> (i32) {
// CHECK-NEXT: case 1 {
// CHECK-NOT: case
// CHECK: default {
func.func @into_default(%n: i64, %x: i32) -> i32 {
  %r = idr.match_lit %n : i64 -> (i32) {
  case 0 {
    %c = arith.constant 7 : i32
    idr.yield %c : i32
  }
  case 1 {
    idr.yield %x : i32
  }
  case 2 {
    %c = arith.constant 7 : i32
    idr.yield %c : i32
  }
  default {
    %c = arith.constant 7 : i32
    idr.yield %c : i32
  }
  }
  return %r : i32
}

// Without a default, two equal cases become it; a case that reads its
// fields stays.
// CHECK-LABEL: func.func @new_default(
// CHECK: idr.match %{{.*}} : !idr.data<@C> -> (i64) {
// CHECK-NEXT: case @G(%[[F:.*]]: i64) {
// CHECK-NEXT: idr.yield %[[F]] : i64
// CHECK-NEXT: }
// CHECK-NEXT: default {
// CHECK-NEXT: %[[S:.*]] = arith.addi
// CHECK-NEXT: idr.yield %[[S]] : i64
// CHECK-NEXT: }
// CHECK-NEXT: }
func.func @new_default(%c: !idr.data<@C>, %x: i64) -> i64 {
  %r = idr.match %c : !idr.data<@C> -> (i64) {
  case @R() {
    %s = arith.addi %x, %x : i64
    idr.yield %s : i64
  }
  case @G(%f: i64) {
    idr.yield %f : i64
  }
  case @B() {
    %s = arith.addi %x, %x : i64
    idr.yield %s : i64
  }
  }
  return %r : i64
}

// When every region is the same, one is left and it is inlined.
// CHECK-LABEL: func.func @all_same(
// CHECK-SAME: %{{.*}}: !idr.data<@C>, %[[X:.*]]: i64)
// CHECK-NEXT: %[[S:.*]] = arith.muli %[[X]], %[[X]] : i64
// CHECK-NEXT: return %[[S]]
func.func @all_same(%c: !idr.data<@C>, %x: i64) -> i64 {
  %r = idr.match %c : !idr.data<@C> -> (i64) {
  case @R() {
    %s = arith.muli %x, %x : i64
    idr.yield %s : i64
  }
  case @G(%unused: i64) {
    %s = arith.muli %x, %x : i64
    idr.yield %s : i64
  }
  default {
    %s = arith.muli %x, %x : i64
    idr.yield %s : i64
  }
  }
  return %r : i64
}
