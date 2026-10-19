// RUN: idris-mlir-opt %s --idr-bufferize -o %t.mlir
// RUN: %status 1 idris-mlir-opt %t.mlir --idr-expect=holds=in-place=@leak -o /dev/null 2> %t.err
// RUN: FileCheck %s < %t.err
// A link of a linear thread (a release of a buffer a use began) is in place
// whenever nothing reads the buffer after it. Here the module reads it
// after its release, so the release writes a copy: bufferization keeps
// the program, at the cost of the copy, and never refuses it.
// CHECK: expected in-place: memref.copy {{.*}} in @leak
idr.program @"link-read-after-release" root(@root) stage(first) {
  idr.func @leak(%a: !idr.lin<tensor<?xi64>>) -> (!idr.lin<tensor<?xi64>>, i64) {
    %c0 = arith.constant 0 : index
    %seven = arith.constant 7 : i64
    %t = idr.lin.use %a : !idr.lin<tensor<?xi64>>
    %t1 = tensor.insert %seven into %t[%c0] : tensor<?xi64>
    %l = idr.lin.enter %t1 : !idr.lin<tensor<?xi64>>
    %v = tensor.extract %t1[%c0] : tensor<?xi64>
    return %l, %v : !idr.lin<tensor<?xi64>>, i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
