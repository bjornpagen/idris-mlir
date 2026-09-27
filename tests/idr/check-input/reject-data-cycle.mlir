// RUN: not idris-mlir-opt %s --idr-check-input 2>&1 | FileCheck %s
// rule: IDR-DATA-4
// CHECK: idr contract violation: data types are recursive (IDR-DATA-4)
module attributes {idr.version = 0 : i64, idr.entry = @r, idr.entry_kind = "int"} {
  idr.data @A {
    idr.ctor @ToB tag 0 fields [!idr.data<@B>] quantities ["w"]
  }
  idr.data @B {
    idr.ctor @ToA tag 0 fields [!idr.data<@A>] quantities ["w"]
  }
  func.func private @r() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}
