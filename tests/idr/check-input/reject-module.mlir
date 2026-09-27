// RUN: not idris-mlir-opt %s -split-input-file --idr-check-input 2>&1 | FileCheck %s
// rule: IDR-MOD-1

// CHECK: idr contract violation: idr.version must be 0, 1, 2 or 3
module attributes {idr.version = 7 : i64, idr.entry = @r, idr.entry_kind = "int"} {
}

// -----

// CHECK: idr contract violation: idr.entry must name a func.func
module attributes {idr.version = 0 : i64, idr.entry = @missing, idr.entry_kind = "int"} {
}

// -----

// CHECK: idr contract violation: an int entry has type () -> i64
module attributes {idr.version = 0 : i64, idr.entry = @r, idr.entry_kind = "int"} {
  func.func private @r(%x: i64 {idr.quantity = "w"}) -> i64 attributes {idr.name = "r"} {
    return %x : i64
  }
}

// -----

// CHECK: idr contract violation: an io entry has type (!idr.world) -> T, from version 1
module attributes {idr.version = 0 : i64, idr.entry = @r, idr.entry_kind = "io"} {
  func.func private @r() -> i64 attributes {idr.name = "r"} {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}

// -----

// CHECK: idr contract violation: the symbol @main is reserved for the C entry point (LOW-ENTRY-1)
module attributes {idr.version = 0 : i64, idr.entry = @main, idr.entry_kind = "int"} {
  func.func private @main() -> i64 attributes {idr.name = "main"} {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}
