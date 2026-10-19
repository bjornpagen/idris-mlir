// RUN: idris-mlir-opt %s -o %t.none.mlir
// RUN: idris-mlir-opt %s --idr-columns --mlir-disable-threading -mlir-debug-counter=idr-columns-convert-count=0 -o %t.skipped.mlir
// RUN: diff %t.none.mlir %t.skipped.mlir
// RUN: idris-mlir-opt %s --idr-columns -o %t.done.mlir
// RUN: %status 1 diff %t.none.mlir %t.done.mlir
// RUN: %differential %s %t.done.mlir
// With every action skipped the pass is the identity, and with none it
// changes the module. The root reads a byte, tabulates that many records
// and prints the first field of each of three of them and the sum of the
// second, and the program prints after the pass what it printed before,
// on every byte.
!P = !idr.data<"P", plain [@MkP(i64, f64)]>
idr.program @columns root(@root) stage(first) {
  idr.func @pairs(%n: index) -> tensor<?x!P> {
    %t = idr.tabulate [%n] {
    ^bb0(%i: index):
      %x = arith.index_cast %i : index to i64
      %d = arith.sitofp %x : i64 to f64
      %p = idr.con !P @MkP(%x : i64, %d : f64)
      idr.array.yield %p : !P
    } : tensor<?x!P>
    return %t : tensor<?x!P>
  }
  idr.func @first(%t: tensor<?x!P>, %i: index) -> i64 {
    %p = tensor.extract %t[%i] : tensor<?x!P>
    %x = idr.field %p : !P @MkP[0] -> i64
    return %x : i64
  }
  idr.func @second(%t: tensor<?x!P>, %i: index) -> f64 {
    %p = tensor.extract %t[%i] : tensor<?x!P>
    %d = idr.field %p : !P @MkP[1] -> f64
    return %d : f64
  }
  idr.func @root(%w: !idr.world) -> !idr.world {
    %ch, %w0 = idr.io.get_byte %w
    %b = arith.extui %ch : i32 to i64
    %c1 = arith.constant 1 : i64
    %c2 = arith.constant 2 : i64
    %b1 = arith.addi %b, %c1 : i64
    %n = arith.index_cast %b1 : i64 to index
    %t = idr.call @pairs(%n) : (index) -> tensor<?x!P>
    %c0 = arith.constant 0 : index
    %ci1 = arith.constant 1 : index
    %half = arith.divui %b1, %c2 : i64
    %mid = arith.index_cast %half : i64 to index
    %last = arith.index_cast %b : i64 to index
    %x0 = idr.call @first(%t, %c0) : (tensor<?x!P>, index) -> i64
    %w1 = idr.io.put_sint %x0, %w0 : i64
    %x1 = idr.call @first(%t, %mid) : (tensor<?x!P>, index) -> i64
    %w2 = idr.io.put_sint %x1, %w1 : i64
    %x2 = idr.call @first(%t, %last) : (tensor<?x!P>, index) -> i64
    %w3 = idr.io.put_sint %x2, %w2 : i64
    %zero = arith.constant 0.0 : f64
    %sum = scf.for %i = %c0 to %n step %ci1 iter_args(%acc = %zero) -> (f64) {
      %d = idr.call @second(%t, %i) : (tensor<?x!P>, index) -> f64
      %acc1 = arith.addf %acc, %d : f64
      scf.yield %acc1 : f64
    }
    %w4 = idr.io.put_double %sum, %w3
    return %w4 : !idr.world
  }
}
