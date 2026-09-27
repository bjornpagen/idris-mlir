// RUN: not idris-mlir-opt %s --idr-check-input 2>&1 | FileCheck %s
// rule: IDR-MOD-1, IDR-CRASH-1
// CHECK: idr contract violation: operation needs idr.version 3
module attributes {idr.version = 2 : i64, idr.entry = @r, idr.entry_kind = "int"} {
  func.func private @r() -> i64 {
    %c = idr.crash "no" : i64
    return %c : i64
  }
}
