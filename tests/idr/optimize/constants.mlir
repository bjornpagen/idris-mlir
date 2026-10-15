// RUN: idris-mlir-opt %s --idr-optimize | FileCheck %s
// NEEDS-ACCEPTANCE: that the constants summary of the recursive @seven reaches @main.
// What a callee returns is part of its summary, computed callee first, so
// a caller folds with it: @seven is on a cycle and never inlined, yet
// every run of it returns 7, so the root adds 1 to 7 at compile time, and
// the call, total and pure, whose result nothing reads any more, goes.
// CHECK-LABEL: idr.func @main(
// CHECK-NOT: call @seven
// CHECK: %[[C:.*]] = arith.constant 8 : i64
// CHECK: return %[[C]] : i64
idr.program @constants root(@main) stage(first) {
  idr.func @seven(%n: i64) -> i64 attributes {total} {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      %c = arith.constant 7 : i64
      idr.yield %c : i64
    }
    default {
      %one = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %x = idr.call @seven(%m) : (i64) -> i64
      idr.yield %x : i64
    }
    }
    return %r : i64
  }
  idr.func @main(%w: !idr.world) -> (i64, !idr.world) {
    %b, %w1 = idr.io.get_byte %w
    %n = arith.extui %b : i32 to i64
    %r = idr.call @seven(%n) : (i64) -> i64
    %one = arith.constant 1 : i64
    %s = arith.addi %r, %one : i64
    return %s, %w1 : i64, !idr.world
  }
}
