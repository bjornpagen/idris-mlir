// RUN: idris-mlir-opt %s --idr-bufferize -o %t.mlir
// RUN: %status 1 idris-mlir-opt %t.mlir --idr-expect=holds=in-place=@thawed -o /dev/null 2> %t.err
// RUN: FileCheck %s < %t.err
// NEEDS-ACCEPTANCE: the allocation a copy targets: `idr::bufferize::copies` reads a memref.copy into a memref.alloc (C15 section 2), the buffer idr-rc later adopts (C14); in-place is read right after idr-bufferize.
// Thawing a constant array writes a copy of it: the constant's buffer is
// static data, never writable, so its release at the thread's head copies
// under every reading of the program, and bufferization succeeds with the
// copy in place of the write.
// CHECK: expected in-place: memref.copy copies a buffer in @thawed
module {
  idr.func private @thawed() -> i64 {
    %c0 = arith.constant 0 : index
    %c = arith.constant dense<[1, 2, 3]> : tensor<3xi64>
    %l = idr.lin.enter %c : !idr.lin<tensor<3xi64>>
    %u = idr.lin.use %l : !idr.lin<tensor<3xi64>>
    %nine = arith.constant 99 : i64
    %u1 = tensor.insert %nine into %u[%c0] : tensor<3xi64>
    %v = tensor.extract %u1[%c0] : tensor<3xi64>
    return %v : i64
  }
  idr.func @root() -> i64 {
    %v = idr.call @thawed() : () -> i64
    return %v : i64
  }
}
