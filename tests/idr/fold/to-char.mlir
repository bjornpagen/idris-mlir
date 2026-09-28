// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s
module {
  // CHECK-LABEL: func.func @chars
  // CHECK-DAG: %[[L:.*]] = arith.constant 955 : i32
  // CHECK-DAG: %[[Z:.*]] = arith.constant 0 : i32
  // CHECK-DAG: %[[U:.*]] = arith.constant 200 : i32
  // CHECK: return %[[L]], %[[Z]], %[[Z]], %[[U]]
  func.func @chars() -> (i32, i32, i32, i32) {
    %a = arith.constant 955 : i64
    %b = arith.constant 55296 : i64
    %c = arith.constant -5 : i64
    %d = arith.constant 200 : i8
    %ra = idr.to_char signed %a : i64
    %rb = idr.to_char signed %b : i64
    %rc = idr.to_char signed %c : i64
    %rd = idr.to_char %d : i8
    return %ra, %rb, %rc, %rd : i32, i32, i32, i32
  }
}
