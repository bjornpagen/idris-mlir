// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=structured-loops=@squares -o /dev/null
// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr.func(idr-structure-loops)))' -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=structured-loops=@squares,structured-loops=@table,structured-loops=@guarded -o /dev/null
// A tabulation is its domain and a region from the indices to an element,
// which Emit writes as the op, never as a loop nest, and idr-structure-loops
// lowers one to one: a region over words that only computes, or computes
// and may crash, has every dimension parallel, so it is one linalg op, in
// one dimension or two. Before the lowering the op is there and no linalg
// op is, so the property fails of the module as written.
idr.program @tabulate root(@root) stage(first) {
  idr.func @squares(%n: index) -> tensor<?xi64> {
    %t = idr.tabulate [%n] {
    ^bb0(%i: index):
      %x = arith.index_cast %i : index to i64
      %y = arith.muli %x, %x : i64
      idr.array.yield %y : i64
    } : tensor<?xi64>
    return %t : tensor<?xi64>
  }
  idr.func @table(%m: index, %n: index) -> tensor<?x?xi64> {
    %t = idr.tabulate [%m, %n] {
    ^bb0(%i: index, %j: index):
      %x = arith.index_cast %i : index to i64
      %y = arith.index_cast %j : index to i64
      %ten = arith.constant 10 : i64
      %s = arith.muli %x, %ten : i64
      %z = arith.addi %s, %y : i64
      idr.array.yield %z : i64
    } : tensor<?x?xi64>
    return %t : tensor<?x?xi64>
  }
  idr.func @guarded(%n: index, %d: i64) -> tensor<?xi64> {
    %t = idr.tabulate [%n] {
    ^bb0(%i: index):
      %x = arith.index_cast %i : index to i64
      %g = idr.check.nonzero %d, "division by zero" : i64
      %q = idr.divs %x, %g : i64
      idr.array.yield %q : i64
    } : tensor<?xi64>
    return %t : tensor<?xi64>
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
