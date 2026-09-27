// RUN: not idris-mlir-opt %s -split-input-file --idr-check-input 2>&1 | FileCheck %s
// rule: IDR-MOD-1, IDR-IN-2, IDR-DBL-1

// CHECK: idr contract violation: operation needs idr.version 2
module attributes {idr.version = 1 : i64, idr.entry = @r, idr.entry_kind = "int"} {
  func.func private @r() -> i64 {
    %c = arith.constant 1.5 : f64
    %i = idr.to_int %c : i64
    return %i : i64
  }
}

// -----

// CHECK: idr contract violation: arith flags are not allowed
module attributes {idr.version = 2 : i64, idr.entry = @r, idr.entry_kind = "int"} {
  func.func private @r() -> i64 {
    %c = arith.constant 1.5 : f64
    %d = arith.addf %c, %c fastmath<contract> : f64
    %i = idr.to_int %d : i64
    return %i : i64
  }
}

// -----

// CHECK: idr contract violation: operation not allowed in the input
module attributes {idr.version = 2 : i64, idr.entry = @r, idr.entry_kind = "int"} {
  func.func private @r() -> i64 {
    %c = arith.constant 1.5 : f64
    %d = arith.remf %c, %c : f64
    %i = idr.to_int %d : i64
    return %i : i64
  }
}
