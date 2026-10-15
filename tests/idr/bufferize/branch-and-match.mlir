// RUN: idris-mlir-opt %s --idr-bufferize | FileCheck %s
// NEEDS-ACCEPTANCE: the printed block argument and match result types after idr-bufferize's retyping (C15 section 4.6).
// A linear array that crosses a block's argument (a branch contification
// or inlining made) and a match's yield is no tensor to the analysis: the
// use beyond the boundary starts its own writable root and the release
// before it hands the buffer on. The one retyping at the end of the pass
// gives every wrapped value its buffer's type with its grade: the
// argument and the match's result are !idr.lin<memref<...>>, and no
// tensor type is left.
// CHECK-LABEL: idr.func @branchy(
// CHECK: ^{{.*}}(%{{.*}}: !idr.lin<memref<?xi64>>):
// CHECK: idr.match_lit %{{.*}} : i64 -> (!idr.lin<memref<?xi64>>)
// CHECK-NOT: tensor<
// CHECK: return
idr.program @"branch-and-match" root(@root) stage(first) {
  idr.func @branchy(%a: !idr.lin<tensor<?xi64>>, %k: i64) -> !idr.lin<tensor<?xi64>> {
    cf.br ^next(%a : !idr.lin<tensor<?xi64>>)
  ^next(%b: !idr.lin<tensor<?xi64>>):
    %r = idr.match_lit %k : i64 -> (!idr.lin<tensor<?xi64>>) {
    case 0 {
      idr.yield %b : !idr.lin<tensor<?xi64>>
    }
    default {
      %c0 = arith.constant 0 : index
      %t = idr.lin.use %b : !idr.lin<tensor<?xi64>>
      %t1 = tensor.insert %k into %t[%c0] : tensor<?xi64>
      %l = idr.lin.enter %t1 : !idr.lin<tensor<?xi64>>
      idr.yield %l : !idr.lin<tensor<?xi64>>
    }
    }
    return %r : !idr.lin<tensor<?xi64>>
  }
  idr.func @root() -> i64 {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %c4 = arith.constant 4 : index
    %k = arith.constant 3 : i64
    %zero = arith.constant 0 : i64
    %e = tensor.empty(%c4) : tensor<?xi64>
    %t = scf.for %i = %c0 to %c4 step %c1 iter_args(%a = %e) -> (tensor<?xi64>) {
      %a1 = tensor.insert %zero into %a[%i] : tensor<?xi64>
      scf.yield %a1 : tensor<?xi64>
    }
    %h = idr.lin.enter %t : !idr.lin<tensor<?xi64>>
    %l = idr.call @branchy(%h, %k) : (!idr.lin<tensor<?xi64>>, i64) -> !idr.lin<tensor<?xi64>>
    %u = idr.lin.use %l : !idr.lin<tensor<?xi64>>
    %v = tensor.extract %u[%c0] : tensor<?xi64>
    return %v : i64
  }
}
