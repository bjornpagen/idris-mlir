// RUN: not idris-mlir-opt %s -split-input-file --idr-lower 2>&1 | FileCheck %s
// idr-defunctionalize makes every closure of the program a sum, and every
// suspension a cell of a memo sum, so the lowering has neither to lower:
// one left is the compiler's error, not a program it lowers some other way.
// CHECK: internal error: idr-lower: a closure is left after idr-defunctionalize
// CHECK: internal error: idr-lower: a lazy value is left after idr-defunctionalize
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

// -----

module attributes {idr.program} {
  func.func private @two() -> i64 {
    %r = arith.constant 2 : i64
    return %r : i64
  }
  func.func @Main.main() -> i64 {
    %t = idr.suspend @two() : () -> !idr.lazy<i64>
    %r = idr.force %t : !idr.lazy<i64> -> i64
    return %r : i64
  }
}
