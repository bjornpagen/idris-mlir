// RUN: idris-mlir-opt %s --idr-prune | FileCheck %s
// RUN: idris-mlir-opt %s --idr-prune --symbol-dce --remove-dead-values | FileCheck %s --check-prefix=RDV
// The match region that the constant 1 rules out, and @g, which only that
// region calls, are unreachable: idr-prune ends the region and the body of
// @g in ub.unreachable. remove-dead-values then keeps the module valid
// (upstream/remove-dead-values-unreachable), and the dead region and @g
// are gone.
// CHECK-LABEL: func.func private @g(
// CHECK-NEXT: ub.unreachable
// CHECK-LABEL: func.func @Main.main(
// CHECK: case 0 {
// CHECK-NEXT: ub.unreachable
// CHECK: default {
// CHECK-NEXT: idr.yield
// RDV-NOT: @g
// RDV-LABEL: func.func @Main.main(
module attributes {idr.program} {
  func.func private @g(%x: i64) -> i64 {
    %r = idr.match_lit %x : i64 -> (i64) {
    case 7 {
      idr.crash "seven"
      ub.unreachable
    }
    default {
      idr.yield %x : i64
    }
    }
    return %r : i64
  }
  func.func @Main.main() -> i64 {
    %c1 = arith.constant 1 : i64
    %r = idr.match_lit %c1 : i64 -> (i64) {
    case 0 {
      %y = func.call @g(%c1) : (i64) -> i64
      idr.yield %y : i64
    }
    default {
      idr.yield %c1 : i64
    }
    }
    return %r : i64
  }
}
