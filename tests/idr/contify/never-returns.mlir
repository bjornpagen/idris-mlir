// RUN: idris-mlir-opt %s --idr-contify | FileCheck %s
// A case block that calls its parent back and never returns ends in
// ub.unreachable. Inlined, its body would be a block of its own after the
// call's, and the match region that makes the call holds one block. The
// call stays, as the inliner leaves it.
// CHECK-LABEL: idr.func private @spin(
// CHECK: match_lit
// CHECK: call @spin.case1(
// CHECK: idr.func private @spin.case1(
module {
  idr.func private @spin(%n: i64) -> i64 {
    %c0 = arith.constant 0 : i64
    %more = arith.cmpi sgt, %n, %c0 : i64
    %r = idr.match_lit %more : i1 -> (i64) {
    case 1 {
      %s = idr.call @spin.case1(%n) : (i64) -> i64
      idr.yield %s : i64
    }
    default {
      idr.yield %n : i64
    }
    }
    return %r : i64
  }
  idr.func private @spin.case1(%n: i64) -> i64 {
    %c1 = arith.constant 1 : i64
    %m = arith.subi %n, %c1 : i64
    %s = idr.call @spin(%m) : (i64) -> i64
    idr.crash "returned"
    ub.unreachable
  }
  idr.func @root(%w: !idr.world) -> !idr.world {
    %n = arith.constant 7 : i64
    %r = idr.call @spin(%n) : (i64) -> i64
    %w2 = idr.io.put_int signed %r, %w : i64
    return %w2 : !idr.world
  }
}
