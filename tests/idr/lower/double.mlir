// RUN: idris-mlir-opt %s --idr-check-input --idr-entry --idr-lower | FileCheck %s
// rule: LOW-DBL-1, LOW-DBL-2, IDR-DBL-2
// CHECK-DAG: @__idr_str_{{[0-9]+}}("idris-mlir: cast of a non-finite Double at Main.idr:4:3\0A")
// CHECK-LABEL: func.func private @Main.main(
// CHECK: %[[F:.*]] = math.isfinite
// CHECK: %[[BAD:.*]] = arith.xori %[[F]]
// CHECK: scf.if %[[BAD]]
// CHECK: call @__idr_crash(
// CHECK: %[[W:.*]] = call @__idr_f64_to_i64(
// CHECK: arith.trunci %[[W]] : i64 to i32
// CHECK: call @__idr_put_double(
// CHECK-DAG: func.func private @__idr_put_double(
// CHECK-DAG: func.func private @__idr_ryu_d2d(
// CHECK-DAG: func.func private @__idr_f64_to_i64(
// CHECK-DAG: llvm.mlir.global internal constant @__idr_ryu_pow5_split(
// CHECK-DAG: llvm.mlir.global internal constant @__idr_ryu_pow5_inv_split(
module attributes {idr.version = 2 : i64, idr.entry = @Main.main, idr.entry_kind = "io"} {
  func.func private @Main.main(%w: !idr.world {idr.quantity = "1"}) -> i32 {
    %c = arith.constant 7 : i64
    %d = arith.sitofp %c : i64 to f64
    %x = arith.divf %d, %d : f64
    %i = idr.to_int %x : i32 loc("Main.idr":4:3)
    %w1 = idr.io.put_double %x, %w
    return %i : i32
  }
}
