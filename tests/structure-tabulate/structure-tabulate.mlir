// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=structured-loops=@squares -o /dev/null
// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr.func(idr-structure-loops)))' -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=structured-loops=@squares,structured-loops=@table,structured-loops=@guarded -o /dev/null
// RUN: %differential %s %t.mlir
// A tabulation is its domain and a region from the indices to an element,
// which Emit writes as the op, never as a loop nest, and idr-structure-loops
// lowers one to one: a region over words that only computes, or computes
// and may crash, has every dimension parallel, so it is one linalg op, in
// one dimension or two. Before the lowering the op is there and no linalg
// op is, so the property fails of the module as written. The root makes
// each array at sizes the input byte sets, 0 to 3 and 0 to 2 in each
// dimension, and prints a sum of its elements each weighted by its
// position, so the lowered program must make every element, at its index:
// the differential holds it to the module as written on every byte. The
// divisor is 0 to 2 too, and dividing by 0 crashes, at the first element,
// only where there is one: an empty domain divides nothing.
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
  // The sum of x[i] * (i + 1).
  idr.func @weigh1(%x: tensor<?xi64>, %n: index) -> i64 {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %zero = arith.constant 0 : i64
    %r = scf.for %i = %c0 to %n step %c1 iter_args(%acc = %zero) -> (i64) {
      %e = tensor.extract %x[%i] : tensor<?xi64>
      %j = arith.addi %i, %c1 : index
      %k = arith.index_cast %j : index to i64
      %p = arith.muli %e, %k : i64
      %a = arith.addi %acc, %p : i64
      scf.yield %a : i64
    }
    return %r : i64
  }
  // The sum of x[i][j] * (7i + j + 1).
  idr.func @weigh2(%x: tensor<?x?xi64>, %m: index, %n: index) -> i64 {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %c7 = arith.constant 7 : index
    %zero = arith.constant 0 : i64
    %r = scf.for %i = %c0 to %m step %c1 iter_args(%acc = %zero) -> (i64) {
      %row = scf.for %j = %c0 to %n step %c1 iter_args(%acc2 = %acc) -> (i64) {
        %e = tensor.extract %x[%i, %j] : tensor<?x?xi64>
        %i7 = arith.muli %i, %c7 : index
        %ij = arith.addi %i7, %j : index
        %w = arith.addi %ij, %c1 : index
        %k = arith.index_cast %w : index to i64
        %p = arith.muli %e, %k : i64
        %a = arith.addi %acc2, %p : i64
        scf.yield %a : i64
      }
      scf.yield %row : i64
    }
    return %r : i64
  }
  idr.func @root(%w: !idr.world) -> !idr.world {
    %ch, %w0 = idr.io.get_byte %w
    %b = arith.extui %ch : i32 to i64
    %c3 = arith.constant 3 : i64
    %c4 = arith.constant 4 : i64
    %nb = arith.remui %b, %c4 : i64
    %q = arith.divui %b, %c4 : i64
    %mb = arith.remui %q, %c3 : i64
    %q2 = arith.divui %q, %c3 : i64
    %d = arith.remui %q2, %c3 : i64
    %n = arith.index_cast %nb : i64 to index
    %m = arith.index_cast %mb : i64 to index
    %sq = idr.call @squares(%n) : (index) -> tensor<?xi64>
    %s1 = idr.call @weigh1(%sq, %n) : (tensor<?xi64>, index) -> i64
    %w1 = idr.io.put_sint %s1, %w0 : i64
    %tb = idr.call @table(%m, %n) : (index, index) -> tensor<?x?xi64>
    %s2 = idr.call @weigh2(%tb, %m, %n) : (tensor<?x?xi64>, index, index) -> i64
    %w2 = idr.io.put_sint %s2, %w1 : i64
    %gd = idr.call @guarded(%n, %d) : (index, i64) -> tensor<?xi64>
    %s3 = idr.call @weigh1(%gd, %n) : (tensor<?xi64>, index) -> i64
    %w3 = idr.io.put_sint %s3, %w2 : i64
    return %w3 : !idr.world
  }
}
