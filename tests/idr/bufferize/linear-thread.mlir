// RUN: idris-mlir-opt %s --idr-bufferize -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=in-place=@fill,in-place -o /dev/null
// NEEDS-ACCEPTANCE: the allocation a copy targets: `idr::bufferize::copies` reads a memref.copy into a memref.alloc, the buffer idr-rc later adopts; in-place is read right after idr-bufferize.
// A linear array's thread is written in place: @fill takes the array at
// quantity one, unwraps it, writes every element and wraps it again for
// its caller, and nothing is copied, in @fill or anywhere: the root's
// fresh array is a thread's head no one reads after it, so its release
// copies nothing either. The grade is kept on the buffer.
idr.program @"linear-thread" root(@root) stage(first) {
  idr.func @fill(%a: !idr.lin<tensor<?xi64>>, %n: index) -> !idr.lin<tensor<?xi64>> {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %t = idr.lin.use %a : !idr.lin<tensor<?xi64>>
    %r = scf.for %i = %c0 to %n step %c1 iter_args(%b = %t) -> (tensor<?xi64>) {
      %x = arith.index_cast %i : index to i64
      %b1 = tensor.insert %x into %b[%i] : tensor<?xi64>
      scf.yield %b1 : tensor<?xi64>
    }
    %l = idr.lin.enter %r : !idr.lin<tensor<?xi64>>
    return %l : !idr.lin<tensor<?xi64>>
  }
  idr.func @root() -> i64 {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %c8 = arith.constant 8 : index
    %zero = arith.constant 0 : i64
    %e = tensor.empty(%c8) : tensor<?xi64>
    %t = scf.for %i = %c0 to %c8 step %c1 iter_args(%a = %e) -> (tensor<?xi64>) {
      %a1 = tensor.insert %zero into %a[%i] : tensor<?xi64>
      scf.yield %a1 : tensor<?xi64>
    }
    %h = idr.lin.enter %t : !idr.lin<tensor<?xi64>>
    %l = idr.call @fill(%h, %c8) : (!idr.lin<tensor<?xi64>>, index) -> !idr.lin<tensor<?xi64>>
    %u = idr.lin.use %l : !idr.lin<tensor<?xi64>>
    %v = tensor.extract %u[%c1] : tensor<?xi64>
    return %v : i64
  }
}
