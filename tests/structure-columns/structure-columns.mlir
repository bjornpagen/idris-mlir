// RUN: idris-mlir-opt %s --idr-columns -o %t.mlir
// RUN: %differential %s %t.mlir
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=signature=@pairs:(index)->(tensor<?xi64>,tensor<?xf64>),signature=@first:(tensor<?xi64>,tensor<?xf64>,index)->i64' -o /dev/null
// A tensor of records of one plain constructor is one tensor per field:
// what makes it yields each field into its own column, a signature takes
// and gives the columns, and a read of an element builds the record from
// each column at its index, which the fields' reads then take apart. The
// root makes 1 to 4 records and reads both fields of the record at an
// index, the first, the last or one between, as the input byte sets: the
// columns' program prints what the records' program printed, on every
// byte.
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
    %x = idr.field %p : !P @MkP[1] -> f64
    return %x : f64
  }
  idr.func @root(%w: !idr.world) -> !idr.world {
    %ch, %w0 = idr.io.get_byte %w
    %b = arith.extui %ch : i32 to i64
    %c4 = arith.constant 4 : i64
    %one = arith.constant 1 : i64
    %r = arith.remui %b, %c4 : i64
    %n1 = arith.addi %r, %one : i64
    %q = arith.divui %b, %c4 : i64
    %i1 = arith.remui %q, %n1 : i64
    %n = arith.index_cast %n1 : i64 to index
    %i = arith.index_cast %i1 : i64 to index
    %t = idr.call @pairs(%n) : (index) -> tensor<?x!P>
    %x = idr.call @first(%t, %i) : (tensor<?x!P>, index) -> i64
    %d = idr.call @second(%t, %i) : (tensor<?x!P>, index) -> f64
    %c2 = arith.constant 2.5 : f64
    %d2 = arith.mulf %d, %c2 : f64
    %y = arith.fptosi %d2 : f64 to i64
    %w1 = idr.io.put_sint %x, %w0 : i64
    %w2 = idr.io.put_sint %y, %w1 : i64
    return %w2 : !idr.world
  }
}
