// NEEDS-ACCEPTANCE: that idr-structure-loops lowers a tabulation of cells whose size only the cells know at ranks 0, 1 and 2 and over an empty domain, each to the first cell made at the zero index and one loop over the rest of the domain's linear index, leaving no array op.
// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr.func(idr-structure-loops)))' -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=structured-loops=@rank0,structured-loops=@rank1,structured-loops=@rank2,structured-loops=@empty -o /dev/null
// Each tabulation here makes rows whose length its type leaves dynamic: the
// arrays get their size from the first row, made at the domain's zero
// index before them, and the rest of the domain runs as one loop over its
// linear index from 1, in row-major order. The domain's size is the product
// of its extents, one at rank 0, where the loop is empty; an empty domain
// makes no row. Each row is itself a tabulation of words, a linalg op.
idr.program @dynamic root(@root) stage(first) {
  idr.func @rank0(%k: index) -> tensor<?xi64> {
    %t = idr.tabulate [] {
      %row = idr.tabulate [%k] {
      ^bb0(%j: index):
        %x = arith.index_cast %j : index to i64
        idr.array.yield %x : i64
      } : tensor<?xi64>
      idr.array.yield %row : tensor<?xi64>
    } : tensor<?xi64>
    return %t : tensor<?xi64>
  }
  idr.func @rank1(%n: index, %k: index) -> tensor<?x?xi64> {
    %t = idr.tabulate [%n] {
    ^bb0(%i: index):
      %row = idr.tabulate [%k] {
      ^bb0(%j: index):
        %x = arith.index_cast %i : index to i64
        %y = arith.index_cast %j : index to i64
        %z = arith.addi %x, %y : i64
        idr.array.yield %z : i64
      } : tensor<?xi64>
      idr.array.yield %row : tensor<?xi64>
    } : tensor<?x?xi64>
    return %t : tensor<?x?xi64>
  }
  idr.func @rank2(%m: index, %n: index, %k: index) -> tensor<?x?x?xi64> {
    %t = idr.tabulate [%m, %n] {
    ^bb0(%i: index, %l: index):
      %row = idr.tabulate [%k] {
      ^bb0(%j: index):
        %x = arith.index_cast %i : index to i64
        %y = arith.index_cast %l : index to i64
        %z = arith.index_cast %j : index to i64
        %s = arith.addi %x, %y : i64
        %u = arith.addi %s, %z : i64
        idr.array.yield %u : i64
      } : tensor<?xi64>
      idr.array.yield %row : tensor<?xi64>
    } : tensor<?x?x?xi64>
    return %t : tensor<?x?x?xi64>
  }
  idr.func @empty(%k: index) -> tensor<?x?xi64> {
    %zero = arith.constant 0 : index
    %t = idr.tabulate [%zero] {
    ^bb0(%i: index):
      %row = idr.tabulate [%k] {
      ^bb0(%j: index):
        %x = arith.index_cast %j : index to i64
        idr.array.yield %x : i64
      } : tensor<?xi64>
      idr.array.yield %row : tensor<?xi64>
    } : tensor<?x?xi64>
    return %t : tensor<?x?xi64>
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
