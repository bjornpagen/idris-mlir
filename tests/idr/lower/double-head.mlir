// RUN: idris-mlir-opt %s --idr-check-input --idr-entry --idr-lower | FileCheck %s
// rule: IDR-DBL-3, LOW-DBL-4
// CHECK-LABEL: func.func private @Main.main(
// CHECK: call @__idr_double_head(%{{.*}}) : (f64) -> i32
// CHECK: func.func private @__idr_double_head(
// CHECK: call @__idr_ryu_d2d(
module attributes {idr.version = 3 : i64, idr.entry = @Main.main, idr.entry_kind = "int"} {
  func.func private @Main.main() -> i64 attributes {idr.name = "main"} {
    %x = arith.constant 2.5 : f64
    %y = arith.divf %x, %x : f64
    %c = idr.double_head %y
    %r = arith.extui %c : i32 to i64
    return %r : i64
  }
}
