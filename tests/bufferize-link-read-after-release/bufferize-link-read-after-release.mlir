// RUN: idris-mlir-opt %s --idr-bufferize -o %t.mlir
// RUN: %status 1 idris-mlir-opt %t.mlir --idr-expect=holds=in-place=@leak -o /dev/null 2> %t.err
// RUN: FileCheck %s < %t.err
// RUN: %differential %s %t.mlir
// A link of a linear thread (a release of a buffer a use began) is in place
// whenever nothing reads the buffer after it. Here the module reads it
// after its release, so the release writes a copy: bufferization keeps
// the program, at the cost of the copy, and never refuses it.
// CHECK: expected in-place: memref.copy {{.*}} in @leak
// The root runs @leak on an array made from the byte it reads, and the
// program prints after the pass what it printed before, on every byte: the
// read sees the write.
idr.program @"link-read-after-release" root(@root) stage(first) types #idr.types<> {
  idr.func @leak(%a: !idr.lin<tensor<?xi64>>) -> (!idr.lin<tensor<?xi64>>, i64) {
    %c0 = arith.constant 0 : index
    %seven = arith.constant 7 : i64
    %t = idr.lin.use %a : !idr.lin<tensor<?xi64>>
    %t1 = tensor.insert %seven into %t[%c0] : tensor<?xi64>
    %l = idr.lin.enter %t1 : !idr.lin<tensor<?xi64>>
    %v = tensor.extract %t1[%c0] : tensor<?xi64>
    return %l, %v : !idr.lin<tensor<?xi64>>, i64
  }
  // The program's root runs @leak on an array of the byte it reads, as
  // long as the byte modulo 8 plus 1, and prints what the read saw and
  // what the array holds after: the read sees the write.
  idr.func @root(%w: !idr.world) -> !idr.world {
    %ch, %w0 = idr.io.get_byte %w
    %x = arith.extui %ch : i32 to i64
    %c7 = arith.constant 7 : i64
    %c1i = arith.constant 1 : i64
    %k = arith.andi %x, %c7 : i64
    %k1 = arith.addi %k, %c1i : i64
    %n = arith.index_cast %k1 : i64 to index
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %e = tensor.empty(%n) : tensor<?xi64>
    %t = scf.for %i = %c0 to %n step %c1 iter_args(%a = %e) -> (tensor<?xi64>) {
      %a1 = tensor.insert %x into %a[%i] : tensor<?xi64>
      scf.yield %a1 : tensor<?xi64>
    }
    %h = idr.lin.enter %t : !idr.lin<tensor<?xi64>>
    %l, %v = idr.call @leak(%h) : (!idr.lin<tensor<?xi64>>) -> (!idr.lin<tensor<?xi64>>, i64)
    %w1 = idr.io.put_sint %v, %w0 : i64
    %u = idr.lin.use %l : !idr.lin<tensor<?xi64>>
    %zero = arith.constant 0 : i64
    %s = scf.for %i = %c0 to %n step %c1 iter_args(%acc = %zero) -> (i64) {
      %y = tensor.extract %u[%i] : tensor<?xi64>
      %acc1 = arith.addi %acc, %y : i64
      scf.yield %acc1 : i64
    }
    %w2 = idr.io.put_sint %s, %w1 : i64
    return %w2 : !idr.world
  }
}
