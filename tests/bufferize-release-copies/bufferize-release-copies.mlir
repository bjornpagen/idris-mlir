// RUN: idris-mlir-opt %s --idr-bufferize -o %t.mlir
// RUN: %status 1 idris-mlir-opt %t.mlir --idr-expect=holds=in-place=@reads -o /dev/null 2> %t.err
// RUN: FileCheck %s < %t.err
// RUN: %differential %s %t.mlir
// A release hands an array to a linear thread. At a thread's head (thaw:
// an array no use began) the array is a value, which the program may read
// again after the release: then the release copies, as the program's
// meaning says, and the thread writes the copy. The copy is allowed; it
// is what in-place reports.
// CHECK: expected in-place: memref.copy {{.*}} in @reads
// The root runs @reads on an array as long as the byte it reads says, and
// the program prints after the pass what it printed before, on every byte:
// the read before the release sees the array as it was.
idr.program @"release-copies" root(@root) stage(first) types #idr.types<> {
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
  // The program's root runs @reads on an array as long as the byte it
  // reads modulo 16, plus 1.
  idr.func @root(%w: !idr.world) -> !idr.world {
    %ch, %w0 = idr.io.get_byte %w
    %b = arith.extui %ch : i32 to i64
    %c15 = arith.constant 15 : i64
    %c1 = arith.constant 1 : i64
    %k = arith.andi %b, %c15 : i64
    %k1 = arith.addi %k, %c1 : i64
    %n = arith.index_cast %k1 : i64 to index
    %v = idr.call @reads(%n) : (index) -> i64
    %w1 = idr.io.put_sint %v, %w0 : i64
    return %w1 : !idr.world
  }
}
