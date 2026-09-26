// RUN: not idris-mlir-opt %s --idr-check-input 2>&1 | FileCheck %s
// rule: IDR-DATA-4
// CHECK: idr contract violation: data types are recursive (IDR-DATA-4)
module attributes {idr.version = 0 : i64, idr.entry = @r, idr.entry_kind = "int"} {
  idr.data @A attributes {idr.name = "A"} {
    idr.ctor @ToB tag 0 fields [!idr.data<@B>] quantities ["w"] {idr.name = "ToB"}
  }
  idr.data @B attributes {idr.name = "B"} {
    idr.ctor @ToA tag 0 fields [!idr.data<@A>] quantities ["w"] {idr.name = "ToA"}
  }
  func.func private @r() -> i64 attributes {idr.name = "r"} {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}
