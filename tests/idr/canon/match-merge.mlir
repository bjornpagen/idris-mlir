// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s
// RUN: idris-mlir-opt %s --canonicalize=test-convergence=true -o /dev/null
// Identical regions merge: a case that does what the default does goes to
// the default, and without a default, cases that do the same become it.


// CHECK-LABEL: idr.func private @into_default(
// CHECK: match_lit %{{.*}} : i64 -> (i32) {
// CHECK-NEXT: case 1 {
// CHECK-NOT: case
// CHECK: default {
!C = !idr.data<"C", plain [@R(), @G(i64), @B()]>
idr.func private @into_default(%n: i64, %x: i32) -> i32 {
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
// CHECK-LABEL: idr.func private @new_default(
// CHECK: match %{{.*}} : !C -> (i64) {
// CHECK-NEXT: case @G(%[[F:.*]]: i64) {
// CHECK-NEXT: idr.yield %[[F]] : i64
// CHECK-NEXT: }
// CHECK-NEXT: default {
// CHECK-NEXT: %[[S:.*]] = arith.addi
// CHECK-NEXT: idr.yield %[[S]] : i64
// CHECK-NEXT: }
// CHECK-NEXT: }
idr.func private @new_default(%c: !C, %x: i64) -> i64 {
  %r = idr.match %c : !C -> (i64) {
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
// CHECK-LABEL: idr.func private @all_same(
// CHECK-SAME: %{{.*}}: !C, %[[X:.*]]: i64)
// CHECK-NEXT: %[[S:.*]] = arith.muli %[[X]], %[[X]] : i64
// CHECK-NEXT: return %[[S]]
idr.func private @all_same(%c: !C, %x: i64) -> i64 {
  %r = idr.match %c : !C -> (i64) {
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
