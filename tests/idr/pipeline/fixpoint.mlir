// RUN: idris-mlir-opt %s --idr-simplify > %t1.mlir
// RUN: idris-mlir-opt %t1.mlir --idr-simplify > %t2.mlir
// RUN: diff %t1.mlir %t2.mlir
// RUN: FileCheck %s < %t1.mlir
// rule: OPT-IDEM-1, OPT-PIPE-5, ELIM-SPEC-1, ELIM-G-1
// The simplify loop runs to a fixpoint, so running it again changes nothing.
// The closure passed to the recursive @pow is specialized away: the clone
// applies a constant closure, which becomes a direct call to @inc and is
// inlined in the next round; @pow and @inc are then dead.
// CHECK: module attributes {idr.clone_counts = {pow = 1 : i64}, idr.program}
// CHECK-LABEL: func.func @Main.main(
// CHECK: call @pow$spec$1(
// CHECK-NOT: func.func private @pow(
// CHECK-NOT: @inc
// CHECK-LABEL: func.func private @pow$spec$1(
// CHECK: arith.addi
// CHECK: call @pow$spec$1(
module attributes {idr.program} {
  func.func private @inc(%x: i64 {idr.quantity = "w"}) -> i64 attributes {idr.total} {
    %c1 = arith.constant 1 : i64
    %y = arith.addi %x, %c1 : i64
    return %y : i64
  }
  func.func private @pow(%f: !idr.fn<(i64) -> (i64)> {idr.quantity = "w"}, %n: i64 {idr.quantity = "w"}, %x: i64 {idr.quantity = "w"}) -> i64 attributes {idr.total} {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %x : i64
    }
    default {
      %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %r = func.call @pow(%f, %m, %y) : (!idr.fn<(i64) -> (i64)>, i64, i64) -> i64
      idr.yield %r : i64
    }
    }
    return %r : i64
  }
  func.func @Main.main(%w: !idr.world {idr.quantity = "1"}) -> !idr.world {
    %c, %w1 = idr.io.get_char %w
    %n = arith.extui %c : i32 to i64
    %f = idr.closure @inc() : () -> !idr.fn<(i64) -> (i64)>
    %r = func.call @pow(%f, %n, %n) : (!idr.fn<(i64) -> (i64)>, i64, i64) -> i64
    %w2 = idr.io.put_int signed %r, %w1 : i64
    return %w2 : !idr.world
  }
}
