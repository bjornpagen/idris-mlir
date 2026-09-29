// RUN: idris-mlir-opt %s --idr-lower | FileCheck %s --implicit-check-not=idr.lin
// Linearity has no runtime form: a linear value is lowered as the value
// itself, and entering or using one is nothing. The predecessor of a big is
// the runtime's subtraction of one.
// CHECK-LABEL: func.func private @pass(
// CHECK-SAME: %[[X:.*]]: i64
// CHECK: return %[[X]] : i64
// CHECK-LABEL: func.func private @pred(
// CHECK: llvm.call @idris_rt_big_sub
module attributes {idr.program} {
  func.func private @pass(%x: !idr.lin<i64>) -> i64 {
    %v = idr.lin.use %x : !idr.lin<i64>
    return %v : i64
  }
  func.func private @pred(%n: !idr.big) -> !idr.big {
    %p = idr.big.pred %n
    return %p : !idr.big
  }
  func.func @Prog.main() -> i64 {
    %c = arith.constant 7 : i64
    %e = idr.lin.enter %c : !idr.lin<i64>
    %r = func.call @pass(%e) : (!idr.lin<i64>) -> i64
    return %r : i64
  }
}
