// RUN: idris-mlir-opt %s --idr-bufferize -o %t.mlir
// RUN: %status 1 idris-mlir-opt %t.mlir --idr-expect=holds=in-place=@thawed -o /dev/null 2> %t.err
// RUN: FileCheck %s < %t.err
// RUN: %differential %s %t.mlir
// Thawing a constant array writes a copy of it: the constant's buffer is
// static data, never writable, so its release at the thread's head copies
// under every reading of the program, and bufferization succeeds with the
// copy in place of the write.
// CHECK: expected in-place: memref.copy {{.*}} in @thawed
// The root thaws the constant twice, and the program prints after the pass
// what it printed before: 99 twice, the second thaw starting again from the
// constant.
idr.program @"release-constant" root(@root) stage(first) types #idr.types<> {
  idr.func @thawed() -> i64 {
    %c0 = arith.constant 0 : index
    %c = arith.constant dense<[1, 2, 3]> : tensor<3xi64>
    %l = idr.lin.enter %c : !idr.lin<tensor<3xi64>>
    %u = idr.lin.use %l : !idr.lin<tensor<3xi64>>
    %nine = arith.constant 99 : i64
    %u1 = tensor.insert %nine into %u[%c0] : tensor<3xi64>
    %v = tensor.extract %u1[%c0] : tensor<3xi64>
    return %v : i64
  }
  // The program's root prints what @thawed gives twice: the second thaw
  // starts again from the constant, which the first one's write left as
  // it was.
  idr.func @root(%w: !idr.world) -> !idr.world {
    %v = idr.call @thawed() : () -> i64
    %w1 = idr.io.put_sint %v, %w : i64
    %u = idr.call @thawed() : () -> i64
    %w2 = idr.io.put_sint %u, %w1 : i64
    return %w2 : !idr.world
  }
}
