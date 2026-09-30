// RUN: idris-mlir-opt %s --idr-lower | FileCheck %s --implicit-check-not=idr.lin
// Linearity has no runtime form: a linear value is lowered as the value
// itself, and entering or using one is nothing.
// CHECK-LABEL: func.func private @pass(
// CHECK-SAME: %[[X:.*]]: i64
// CHECK: return %[[X]] : i64
module attributes {idr.program} {
  func.func private @pass(%x: !idr.lin<i64>) -> i64 {
    %v = idr.lin.use %x : !idr.lin<i64>
    return %v : i64
  }
  func.func @Prog.main() -> i64 {
    %c = arith.constant 7 : i64
    %e = idr.lin.enter %c : !idr.lin<i64>
    %r = func.call @pass(%e) : (!idr.lin<i64>) -> i64
    return %r : i64
  }
}
