// RUN: sed -n 's|^// CLEAN: ||p' %s > %t.clean.mlir
// RUN: idris-mlir-opt %t.clean.mlir --idr-expect=holds=no-closures -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=no-closures -o /dev/null 2> %t.err
// RUN: FileCheck %s < %t.err
// A module without closures holds; each closure left, built, applied or a
// constant, is one error, in the function that holds it.
// CHECK-DAG: error: expected no-closures: a closure is built in @make
// CHECK-DAG: error: expected no-closures: a closure is applied in @use
// CHECK-DAG: error: expected no-closures: a closure is a constant in @known
// CLEAN: module {
// CLEAN:   func.func @main(%x: i64) -> i64 {
// CLEAN:     %one = arith.constant 1 : i64
// CLEAN:     %r = arith.addi %x, %one : i64
// CLEAN:     return %r : i64
// CLEAN:   }
// CLEAN: }
module {
  func.func private @add(%x: i64, %y: i64) -> i64 {
    %r = arith.addi %x, %y : i64
    return %r : i64
  }
  func.func @make(%x: i64) -> !idr.fn<(i64) -> (i64)> {
    %f = idr.closure @add(%x) : (i64) -> !idr.fn<(i64) -> (i64)>
    return %f : !idr.fn<(i64) -> (i64)>
  }
  func.func @use(%f: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 {
    %r = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
    return %r : i64
  }
  func.func @known() -> !idr.fn<(i64, i64) -> (i64)> {
    %f = idr.constant #idr.closure<@add, []> : !idr.fn<(i64, i64) -> (i64)>
    return %f : !idr.fn<(i64, i64) -> (i64)>
  }
}
