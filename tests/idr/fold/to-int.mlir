// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s
module {
  // Finite constants truncate toward zero and wrap to the result width.
  // CHECK-LABEL: func.func @finite
  // CHECK-DAG: %[[A:.*]] = arith.constant -2 : i64
  // CHECK-DAG: %[[B:.*]] = arith.constant 44 : i8
  // CHECK-DAG: %[[C:.*]] = arith.constant -8446744073709551616 : i64
  // CHECK: return %[[A]], %[[B]], %[[C]]
  func.func @finite() -> (i64, i8, i64) {
    %a = arith.constant -2.75 : f64
    %b = arith.constant 300.5 : f64
    %c = arith.constant 1.0e19 : f64
    %ra = idr.to_int %a : i64
    %rb = idr.to_int %b : i8
    %rc = idr.to_int %c : i64
    return %ra, %rb, %rc : i64, i8, i64
  }
  // The guard of NaN does not fold, and stays although nothing reads it,
  // because it crashes; a dead cast goes, and so does the guard of a finite
  // constant. A cast of NaN with no guard before it does not fold either:
  // NaN has no Int to fold to.
  // CHECK-LABEL: func.func @nan
  // CHECK: idr.check.finite %{{.*}}, "cast of a non-finite Double"
  // CHECK-NOT: idr.check.finite
  // CHECK: %[[R:.*]] = idr.to_int %{{.*}} : i64
  // CHECK-NOT: idr.to_int
  // CHECK: return %[[R]]
  func.func @nan() -> i64 {
    %n = arith.constant 0x7FF8000000000000 : f64
    %f = arith.constant 1.5 : f64
    %ng = idr.check.finite %n, "cast of a non-finite Double"
    %a = idr.to_int %ng : i64
    %fg = idr.check.finite %f, "cast of a non-finite Double"
    %b = idr.to_int %fg : i64
    %r = idr.to_int %n : i64
    return %r : i64
  }
}
