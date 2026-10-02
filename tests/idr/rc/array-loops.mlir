// RUN: idris-mlir-opt %s --idr-rc | FileCheck %s
// RUN: idris-mlir-opt %s --idr-rc --idr-lower -o /dev/null
// A loop over an array of words counts nothing of its own: the array a
// fold reads is borrowed, its init moves into the body as the first
// accumulator, and the body's words hold no reference. A value from
// outside the body that the body consumes (a string stored in a
// constructor on every iteration) takes a reference of its own inside the
// body, once per iteration, and the value's own reference is dropped after
// the loop, not in it: the body runs once per element. The second RUN line
// checks that the owned module lowers.
// CHECK-LABEL: func.func private @total(
// CHECK-NOT: idr.dup
// CHECK-NOT: idr.drop
// CHECK: idr.array.fold
// CHECK-NOT: idr.dup
// CHECK-NOT: idr.drop
// CHECK: return
// CHECK-LABEL: func.func private @lengths(
// CHECK-SAME: %[[S:[^:]*]]: !idr.own<!idr.str>
// CHECK-NOT: idr.dup
// CHECK: idr.array.generate
// CHECK: %[[V:.*]] = idr.borrow %[[S]]
// CHECK: idr.dup %[[V]]
// CHECK: idr.con @Wrap::@W(
// CHECK: idr.yield
// CHECK: }
// CHECK: idr.drop %[[S]]
// CHECK: return
module attributes {idr.program} {
  idr.data @Wrap {
    idr.ctor @W (!idr.str)
  }
  func.func @root(%w: !idr.world) -> !idr.world {
    %n = arith.constant 3 : i64
    %s = idr.constant "s" : !idr.str
    %a, %w1 = func.call @squares(%n, %w) : (i64, !idr.world) -> (memref<?xi64>, !idr.world)
    %t, %w2 = func.call @total(%a, %w1) : (memref<?xi64>, !idr.world) -> (i64, !idr.world)
    %b, %w3 = func.call @lengths(%n, %s, %w2) : (i64, !idr.str, !idr.world) -> (memref<?xi64>, !idr.world)
    return %w3 : !idr.world
  }
  func.func private @squares(%n: i64, %w: !idr.world) -> (memref<?xi64>, !idr.world) {
    %zero = arith.constant 0 : i64
    %a, %w1 = idr.array.generate %n, %zero, %w : i64 -> memref<?xi64> (%i: i64) {
      %sq = arith.muli %i, %i : i64
      idr.yield %sq : i64
    }
    return %a, %w1 : memref<?xi64>, !idr.world
  }
  func.func private @total(%a: memref<?xi64>, %w: !idr.world) -> (i64, !idr.world) {
    %zero = arith.constant 0 : i64
    %s, %w1 = idr.array.fold %a, %zero, %w : memref<?xi64>, i64 -> i64 (%acc: i64, %x: i64, %i: i64) {
      %t = arith.addi %acc, %x : i64
      idr.yield %t : i64
    }
    return %s, %w1 : i64, !idr.world
  }
  func.func private @lengths(%n: i64, %s: !idr.str, %w: !idr.world) -> (memref<?xi64>, !idr.world) {
    %zero = arith.constant 0 : i64
    %a, %w1 = idr.array.generate %n, %zero, %w : i64 -> memref<?xi64> (%i: i64) {
      %p = idr.con @Wrap::@W(%s) : (!idr.str) -> !idr.data<@Wrap>
      %t = idr.tag %p : !idr.data<@Wrap>
      idr.yield %t : i64
    }
    return %a, %w1 : memref<?xi64>, !idr.world
  }
}
