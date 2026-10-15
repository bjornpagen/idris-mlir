// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.func(idr-structure-loops))' -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=counted-loop=@gen -o /dev/null
// RUN: idris-mlir-opt %t.mlir --idr-bufferize --idr-lower | FileCheck %s
// A loop over an array whose body never returns ends in its crash and
// yields poison, which no path reaches: a crash is an effect, so the loop
// stays the frontend's, in order, and lowering keeps the crash at its
// index. It is the program's crash, never the compiler's error.
// CHECK-LABEL: func.func private @gen(
// CHECK: scf.for
// CHECK: llvm.call @idris_rt_crash
// CHECK-NOT: idr.
// CHECK: return
module {
  idr.func private @gen(%n: index) -> tensor<?xi64> {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %e = tensor.empty(%n) : tensor<?xi64>
    %r = scf.for %i = %c0 to %n step %c1 iter_args(%a = %e) -> (tensor<?xi64>) {
      idr.crash "boom"
      %p = ub.poison : tensor<?xi64>
      scf.yield %p : tensor<?xi64>
    }
    return %r : tensor<?xi64>
  }
  idr.func @root() -> i64 {
    %c0 = arith.constant 0 : index
    %c4 = arith.constant 4 : index
    %t = idr.call @gen(%c4) : (index) -> tensor<?xi64>
    %v = tensor.extract %t[%c0] : tensor<?xi64>
    return %v : i64
  }
}
