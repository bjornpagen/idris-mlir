// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr.func(idr-structure-loops)))' -o %t.mlir
// RUN: %differential %s %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=structured-loops=@rank0,structured-loops=@rank1,structured-loops=@rank2,structured-loops=@empty -o /dev/null
// Each tabulation here makes rows whose length its type leaves dynamic: the
// arrays get their size from the first row, made at the domain's zero
// index before them, and the rest of the domain runs as one loop over its
// linear index from 1, in row-major order. The domain's size is the product
// of its extents, one at rank 0, where the loop is empty; an empty domain
// makes no row. Each row is itself a tabulation of words, a linalg op.
// The root makes each at sizes the input byte sets, rows of 1 to 3 words
// over domains of 1 to 3 in each dimension (0 to 2 words at rank 0), and
// prints the sizes and the elements at the corners, the last made last:
// the lowered program prints what the module as written prints, on every
// byte.
idr.program @dynamic root(@root) stage(first) types #idr.types<> {
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
  idr.func @root(%w: !idr.world) -> !idr.world {
    %ch, %w0 = idr.io.get_byte %w
    %b = arith.extui %ch : i32 to i64
    %c3 = arith.constant 3 : i64
    %one = arith.constant 1 : i64
    %kr = arith.remui %b, %c3 : i64
    %q1 = arith.divui %b, %c3 : i64
    %nr = arith.remui %q1, %c3 : i64
    %q2 = arith.divui %q1, %c3 : i64
    %mr = arith.remui %q2, %c3 : i64
    %k1 = arith.addi %kr, %one : i64
    %n1 = arith.addi %nr, %one : i64
    %m1 = arith.addi %mr, %one : i64
    %k0 = arith.index_cast %kr : i64 to index
    %k = arith.index_cast %k1 : i64 to index
    %n = arith.index_cast %n1 : i64 to index
    %m = arith.index_cast %m1 : i64 to index
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %kl = arith.subi %k, %c1 : index
    %nl = arith.subi %n, %c1 : index
    %ml = arith.subi %m, %c1 : index
    %r0 = idr.call @rank0(%k0) : (index) -> tensor<?xi64>
    %d0 = tensor.dim %r0, %c0 : tensor<?xi64>
    %d0i = arith.index_cast %d0 : index to i64
    %w1 = idr.io.put_sint %d0i, %w0 : i64
    %r1 = idr.call @rank1(%n, %k) : (index, index) -> tensor<?x?xi64>
    %a1 = tensor.extract %r1[%c0, %c0] : tensor<?x?xi64>
    %b1 = tensor.extract %r1[%nl, %kl] : tensor<?x?xi64>
    %w2 = idr.io.put_sint %a1, %w1 : i64
    %w3 = idr.io.put_sint %b1, %w2 : i64
    %r2 = idr.call @rank2(%m, %n, %k) : (index, index, index) -> tensor<?x?x?xi64>
    %a2 = tensor.extract %r2[%ml, %c0, %kl] : tensor<?x?x?xi64>
    %b2 = tensor.extract %r2[%ml, %nl, %kl] : tensor<?x?x?xi64>
    %w4 = idr.io.put_sint %a2, %w3 : i64
    %w5 = idr.io.put_sint %b2, %w4 : i64
    %e = idr.call @empty(%k) : (index) -> tensor<?x?xi64>
    %de = tensor.dim %e, %c0 : tensor<?x?xi64>
    %dei = arith.index_cast %de : index to i64
    %w6 = idr.io.put_sint %dei, %w5 : i64
    return %w6 : !idr.world
  }
}
