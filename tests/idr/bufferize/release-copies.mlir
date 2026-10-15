// RUN: idris-mlir-opt %s --idr-bufferize -o %t.mlir
// RUN: %status 1 idris-mlir-opt %t.mlir --idr-expect=holds=in-place=@reads -o /dev/null 2> %t.err
// RUN: FileCheck %s < %t.err
// NEEDS-ACCEPTANCE: the allocation a copy targets: `idr::bufferize::copies` reads a memref.copy into a memref.alloc (C15 section 2), the buffer idr-rc later adopts (C14); in-place is read right after idr-bufferize.
// A release hands an array to a linear thread. At a thread's head (thaw:
// an array no use began) the array is a value, which the program may read
// again after the release: then the release copies, as the program's
// meaning says, and the thread writes the copy. The copy is allowed; it
// is what in-place reports.
// CHECK: expected in-place: memref.copy copies a buffer in @reads
idr.program @"release-copies" root(@root) stage(first) {
  idr.func @reads(%n: index) -> i64 {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %e = tensor.empty(%n) : tensor<?xi64>
    %t = scf.for %i = %c0 to %n step %c1 iter_args(%a = %e) -> (tensor<?xi64>) {
      %x = arith.index_cast %i : index to i64
      %a1 = tensor.insert %x into %a[%i] : tensor<?xi64>
      scf.yield %a1 : tensor<?xi64>
    }
    %l = idr.lin.enter %t : !idr.lin<tensor<?xi64>>
    %before = tensor.extract %t[%c0] : tensor<?xi64>
    %u = idr.lin.use %l : !idr.lin<tensor<?xi64>>
    %nine = arith.constant 99 : i64
    %u1 = tensor.insert %nine into %u[%c0] : tensor<?xi64>
    %after = tensor.extract %u1[%c0] : tensor<?xi64>
    %s = arith.addi %before, %after : i64
    return %s : i64
  }
  idr.func @root() -> i64 {
    %c4 = arith.constant 4 : index
    %v = idr.call @reads(%c4) : (index) -> i64
    return %v : i64
  }
}
