// RUN: idris-mlir-opt %s --sccp --idr-prune --remove-dead-values > %t.mlir
// RUN: FileCheck %s < %t.mlir
// A clone is the function of its key for every call idr-specialize makes of
// it, in later rounds too, not only for the callers it has now: here its
// one caller passes 3, which is no fact of its body. The clone names itself,
// so the interprocedural passes see callers they cannot know: sccp folds no
// 3 into it, no case is pruned as unreachable, and the counter stays a
// parameter.
// CHECK-LABEL: func.func private @count$raise$1(
// CHECK-SAME: %[[K:[a-z0-9_]+]]: i64
// CHECK: idr.match_lit %[[K]]
// CHECK: case 0 {
// CHECK-NEXT: idr.io.put_int
// CHECK: arith.subi %[[K]]
module attributes {idr.program} {
  func.func private @count$raise$1(%k: i64 {idr.hole = 0 : i64}, %w: !idr.world {idr.hole = 1 : i64}) -> !idr.world attributes {idr.origin = "count", idr.clone = #idr.clone<@count$raise$1, #idr.key_apply<"count", 1>>} {
    %r = idr.match_lit %k : i64 -> (!idr.world) {
    case 0 {
      %w1 = idr.io.put_int signed %k, %w : i64
      idr.yield %w1 : !idr.world
    }
    default {
      %one = arith.constant 1 : i64
      %n = arith.subi %k, %one : i64
      %w1 = idr.io.put_int signed %k, %w : i64
      %w2 = func.call @count$raise$1(%n, %w1) : (i64, !idr.world) -> !idr.world
      idr.yield %w2 : !idr.world
    }
    }
    return %r : !idr.world
  }
  func.func @Main.main(%w: !idr.world) -> !idr.world {
    %three = arith.constant 3 : i64
    %r = func.call @count$raise$1(%three, %w) : (i64, !idr.world) -> !idr.world
    return %r : !idr.world
  }
}
