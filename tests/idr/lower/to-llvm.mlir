// RUN: idris-mlir-opt %s --idr-lower --canonicalize --cse --convert-scf-to-cf --convert-to-llvm --reconcile-unrealized-casts | FileCheck %s
// After idr-lower, upstream's conversions take the module to the LLVM
// dialect alone: a closure's code becomes the address of its function, in
// code and in a static closure alike, and no cast is left.
// CHECK-NOT: unrealized_conversion_cast
// CHECK-NOT: func.
// CHECK-DAG: llvm.mlir.global private constant @__idr_closure_{{[0-9]+}}()
// CHECK-DAG: llvm.mlir.addressof @__idr_code_{{[0-9]+}} : !llvm.ptr
// CHECK-DAG: llvm.func @main() -> i32
// CHECK-DAG: llvm.call %{{.*}}(%{{.*}}, %{{.*}}) : !llvm.ptr, (!llvm.ptr, i64) -> i64
module attributes {idr.program} {
  func.func private @add(%k: i64, %x: i64) -> i64 {
    %r = arith.addi %k, %x : i64
    return %r : i64
  }
  func.func private @run(%f: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 {
    %r = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
    return %r : i64
  }
  func.func @Prog.main() -> i64 {
    %c = idr.constant #idr.closure<@add, [40 : i64]> : !idr.fn<(i64) -> (i64)>
    %two = arith.constant 2 : i64
    %d = idr.closure @add(%two) : (i64) -> !idr.fn<(i64) -> (i64)>
    %r = func.call @run(%c, %two) : (!idr.fn<(i64) -> (i64)>, i64) -> i64
    %s = func.call @run(%d, %r) : (!idr.fn<(i64) -> (i64)>, i64) -> i64
    return %s : i64
  }
}
