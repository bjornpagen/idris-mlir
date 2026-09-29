// RUN: not idris-mlir-opt %s --idr-lower 2>&1 | FileCheck %s
// idr-defunctionalize makes every closure of the program a sum, so the
// program's lowering has no closure to lower: one left is the compiler's
// error, not a program it lowers some other way. idr-eval's lowering
// (jit) still meets closures, which tests/idr/lower/closure.mlir lowers.
// CHECK: internal error: idr-lower: a closure is left after idr-defunctionalize
module attributes {idr.program} {
  func.func private @add(%a: i64, %b: i64) -> i64 {
    %r = arith.addi %a, %b : i64
    return %r : i64
  }
  func.func @Main.main() -> i64 {
    %k = arith.constant 1 : i64
    %c = idr.closure @add(%k) : (i64) -> !idr.fn<(i64) -> (i64)>
    %x = arith.constant 2 : i64
    %r = idr.apply %c(%x) : !idr.fn<(i64) -> (i64)>
    return %r : i64
  }
}
