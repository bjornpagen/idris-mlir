// RUN: idris-mlir-opt %s --idr-check-input | FileCheck %s
// rule: IDR-MOD-1, IDR-FN-1, IDR-FN-2, IDR-DATA-5, IDR-IN-1
// CHECK: func.func private @r
module attributes {idr.version = 0 : i64, idr.entry = @r, idr.entry_kind = "int"} {
  idr.data @T {
    idr.ctor @A tag 0 fields [i64] quantities ["w"]
  }
  func.func private @g(%t: !idr.data<@T> {idr.quantity = "w"}, %e: !idr.erased {idr.quantity = "0"}) -> i64 {
    %x = idr.field %t[@A, 0] : !idr.data<@T> -> i64
    return %x : i64
  }
  func.func private @r() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}
