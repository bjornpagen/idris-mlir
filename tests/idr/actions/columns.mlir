// NEEDS-ACCEPTANCE: that skipping every idr-columns-convert action leaves the module as idr-columns received it, and that idr-columns changes it otherwise.
// RUN: idris-mlir-opt %s -o %t.none.mlir
// RUN: idris-mlir-opt %s --idr-columns --mlir-disable-threading -mlir-debug-counter=idr-columns-convert-count=0 -o %t.skipped.mlir
// RUN: diff %t.none.mlir %t.skipped.mlir
// RUN: idris-mlir-opt %s --idr-columns -o %t.done.mlir
// RUN: not diff %t.none.mlir %t.done.mlir
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
  idr.func @root() -> i64 {
    %c0 = arith.constant 0 : index
    %c4 = arith.constant 4 : index
    %t = idr.call @pairs(%c4) : (index) -> tensor<?x!P>
    %x = idr.call @first(%t, %c0) : (tensor<?x!P>, index) -> i64
    return %x : i64
  }
}
