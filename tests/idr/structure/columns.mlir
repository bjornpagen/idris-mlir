// RUN: idris-mlir-opt %s --idr-columns -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=signature=@pairs:(index)->(tensor<?xi64>,tensor<?xf64>),signature=@first:(tensor<?xi64>,tensor<?xf64>,index)->i64 -o /dev/null
// NEEDS-ACCEPTANCE: idr-columns' signatures: a tensor of one-constructor records becomes one tensor per field, in the fields' order.
// A tensor of records of one plain constructor is one tensor per field:
// what makes it yields each field into its own column, a signature takes
// and gives the columns, and a read of an element builds the record from
// each column at its index, which the fields' reads then take apart.
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
