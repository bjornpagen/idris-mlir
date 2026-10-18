// RUN: idris-mlir-opt %s --idr-bufferize -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=in-place=@go -o /dev/null
// NEEDS-ACCEPTANCE: the allocation a copy targets: `idr::bufferize::copies` reads a memref.copy into a memref.alloc, the buffer idr-rc later adopts; in-place is read right after idr-bufferize.
// A recursive function threading a linear array writes it in place on
// every call: the boundary analysis reads each function on a cycle of
// calls with the others, until what each may read and write of its
// operands is settled, so @go's call of itself is known to write only
// the buffer it is given; the caller's release already made that buffer
// the thread's, and each link inside @go is in place by the analysis's
// own check.
idr.program @"recursive-thread" root(@root) stage(first) {
  idr.func @go(%a: !idr.lin<tensor<?xi64>>, %k: i64) -> !idr.lin<tensor<?xi64>> {
    %r = idr.match_lit %k : i64 -> (!idr.lin<tensor<?xi64>>) {
    case 0 {
      idr.yield %a : !idr.lin<tensor<?xi64>>
    }
    default(%d0: i64) {
      %one = arith.constant 1 : i64
      %j = arith.subi %k, %one : i64
      %i = arith.index_cast %j : i64 to index
      %t = idr.lin.use %a : !idr.lin<tensor<?xi64>>
      %t1 = tensor.insert %k into %t[%i] : tensor<?xi64>
      %l = idr.lin.enter %t1 : !idr.lin<tensor<?xi64>>
      %n = idr.call @go(%l, %j) : (!idr.lin<tensor<?xi64>>, i64) -> !idr.lin<tensor<?xi64>>
      idr.yield %n : !idr.lin<tensor<?xi64>>
    }
    }
    return %r : !idr.lin<tensor<?xi64>>
  }
  idr.func @root() -> i64 {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %c8 = arith.constant 8 : index
    %k = arith.constant 8 : i64
    %zero = arith.constant 0 : i64
    %e = tensor.empty(%c8) : tensor<?xi64>
    %t = scf.for %i = %c0 to %c8 step %c1 iter_args(%a = %e) -> (tensor<?xi64>) {
      %a1 = tensor.insert %zero into %a[%i] : tensor<?xi64>
      scf.yield %a1 : tensor<?xi64>
    }
    %h = idr.lin.enter %t : !idr.lin<tensor<?xi64>>
    %l = idr.call @go(%h, %k) : (!idr.lin<tensor<?xi64>>, i64) -> !idr.lin<tensor<?xi64>>
    %u = idr.lin.use %l : !idr.lin<tensor<?xi64>>
    %v = tensor.extract %u[%c0] : tensor<?xi64>
    return %v : i64
  }
}
