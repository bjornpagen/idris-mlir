// RUN: idris-mlir-opt %s --idr-expect=holds=no-closures -o /dev/null
// RUN: %status 1 idris-mlir-opt %S/closures-remain.mlir --idr-expect=holds=no-closures -o /dev/null 2> %t.err
// RUN: FileCheck %s < %t.err
// A module without closures holds; each closure left, built, applied or a
// constant, is one error, in the function that holds it.
// CHECK-DAG: error: expected no-closures: a closure is built in @make
// CHECK-DAG: error: expected no-closures: a closure is applied in @use
// CHECK-DAG: error: expected no-closures: a closure is a constant in @known
module {
  func.func private @inc(%x: i64) -> i64 {
    %one = arith.constant 1 : i64
    %r = arith.addi %x, %one : i64
    return %r : i64
  }
  func.func @main(%x: i64) -> i64 {
    %r = func.call @inc(%x) : (i64) -> i64
    return %r : i64
  }
}
