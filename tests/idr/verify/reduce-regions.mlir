// RUN: printf '#!/bin/sh\nfor op in "idr.match " idr.match_lit idr.lambda idr.delay idr.array.generate idr.array.fold; do\n  if ! grep -q "$op" "$1"; then exit 0; fi\ndone\nexit 1\n' > %t.test
// RUN: chmod +x %t.test
// RUN: idris-mlir-reduce %s --reduction-tree="traversal-mode=0 test=%t.test" -o %t.reduced 2> %t.log
// RUN: FileCheck %s < %t.reduced
// RUN: FileCheck %s --check-prefix=LOG < %t.log
// idris-mlir-reduce erases ops and drops their uses, so a candidate it
// verifies can hold an idr.yield whose operand is gone. The test keeps
// every op with a region, so the reducer works inside each of them. MLIR
// rejects such a yield for its null operand before the region's own checks
// read it, and the reduction ends with every op still there.
// LOG: null operand found
// CHECK: idr.match %
// CHECK: idr.match_lit
// CHECK: idr.lambda
// CHECK: idr.delay
// CHECK: idr.array.generate
// CHECK: idr.array.fold
module {
  idr.data @T {
    idr.ctor @A (i64)
  }
  func.func @regions(%v: !idr.data<@T>, %n: i64, %a: memref<?xi64>, %w: !idr.world)
      -> (i64, i64, !idr.fn<(i64) -> (i64)>, !idr.lazy<i64>, memref<?xi64>, i64, !idr.world) {
    %m = idr.match %v : !idr.data<@T> -> (i64) {
    case @A(%x: i64) {
      %y = arith.addi %x, %x : i64
      idr.yield %y : i64
    }
    }
    %l = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      %one = arith.constant 1 : i64
      idr.yield %one : i64
    }
    default {
      %z = arith.subi %n, %n : i64
      idr.yield %z : i64
    }
    }
    %f = idr.lambda : !idr.fn<(i64) -> (i64)> {
    ^bb0(%x: i64):
      %y = arith.addi %x, %n : i64
      idr.yield %y : i64
    }
    %t = idr.delay : !idr.lazy<i64> {
      %y = arith.muli %n, %n : i64
      idr.yield %y : i64
    }
    %g, %w1 = idr.array.generate %n, %n, %w : i64 -> memref<?xi64> (%i: i64) {
      %y = arith.addi %i, %n : i64
      idr.yield %y : i64
    }
    %s, %w2 = idr.array.fold %a, %n, %w1 : memref<?xi64>, i64 -> i64 (%acc: i64, %x: i64, %i: i64) {
      %y = arith.addi %acc, %x : i64
      idr.yield %y : i64
    }
    return %m, %l, %f, %t, %g, %s, %w2
        : i64, i64, !idr.fn<(i64) -> (i64)>, !idr.lazy<i64>, memref<?xi64>, i64, !idr.world
  }
}
