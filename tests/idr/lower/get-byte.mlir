// RUN: idris-mlir-opt %s --idr-check-input --idr-entry --idr-lower | FileCheck %s
// rule: IDR-IO-2, LOW-IO-4
// CHECK-LABEL: func.func private @Main.main(
// CHECK: call @__idr_get_byte() : () -> i32
// CHECK-LABEL: func.func private @__idr_get_byte(
// CHECK: arith.constant 255 : i32
// CHECK: call @__idr_peek()
module attributes {idr.version = 3 : i64, idr.entry = @Main.main, idr.entry_kind = "io"} {
  func.func private @Main.main(%w: !idr.world {idr.quantity = "1"}) -> i32 {
    %c, %w1 = idr.io.get_byte %w
    return %c : i32
  }
}
