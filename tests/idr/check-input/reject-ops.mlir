// RUN: not idris-mlir-opt %s -split-input-file --idr-check-input 2>&1 | FileCheck %s
// rule: IDR-IN-1, IDR-IN-2, IDR-FN-1, IDR-FN-2, IDR-DATA-5

// CHECK: idr contract violation: operation not allowed in the input
module attributes {idr.version = 0 : i64, idr.entry = @r, idr.entry_kind = "int"} {
  func.func private @r() -> i64 attributes {idr.name = "r"} {
    %c = llvm.mlir.constant(1 : i64) : i64
    return %c : i64
  }
}

// -----

// CHECK: idr contract violation: arith flags are not allowed
module attributes {idr.version = 0 : i64, idr.entry = @r, idr.entry_kind = "int"} {
  func.func private @r() -> i64 attributes {idr.name = "r"} {
    %c = arith.constant 1 : i64
    %d = arith.addi %c, %c overflow<nsw> : i64
    return %d : i64
  }
}

// -----

// CHECK: idr contract violation: functions must be private (IDR-FN-2)
module attributes {idr.version = 0 : i64, idr.entry = @r, idr.entry_kind = "int"} {
  func.func @r() -> i64 attributes {idr.name = "r"} {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}

// -----

// CHECK: idr contract violation: every argument needs idr.quantity (IDR-FN-1)
module attributes {idr.version = 0 : i64, idr.entry = @r, idr.entry_kind = "int"} {
  func.func private @g(%x: i64) -> i64 attributes {idr.name = "g"} {
    return %x : i64
  }
  func.func private @r() -> i64 attributes {idr.name = "r"} {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}

// -----

// CHECK: idr contract violation: missing idr.name (IDR-DATA-5)
module attributes {idr.version = 0 : i64, idr.entry = @r, idr.entry_kind = "int"} {
  func.func private @r() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}

// -----

// CHECK: idr contract violation: operation needs idr.version 1
module attributes {idr.version = 0 : i64, idr.entry = @r, idr.entry_kind = "int"} {
  func.func private @r() -> i64 attributes {idr.name = "r"} {
    %s = idr.str.lit "x" : !idr.str
    %c = arith.constant 0 : i64
    return %c : i64
  }
}

// -----

// CHECK: idr contract violation: result type not allowed
module attributes {idr.version = 0 : i64, idr.entry = @r, idr.entry_kind = "int"} {
  func.func private @r() -> i64 attributes {idr.name = "r"} {
    %f = arith.constant 1.0 : f64
    %c = arith.constant 0 : i64
    return %c : i64
  }
}

// -----

// CHECK: idr contract violation: operation not allowed in the input
module attributes {idr.version = 0 : i64, idr.entry = @r, idr.entry_kind = "int"} {
  func.func private @r() -> i64 attributes {idr.name = "r"} {
    idr.may_loop
    %c = arith.constant 0 : i64
    return %c : i64
  }
}
