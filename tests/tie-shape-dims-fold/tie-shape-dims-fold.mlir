// RUN: idris-mlir-opt %s '--canonicalize=region-simplify=disabled test-convergence=true' -o /dev/null
// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=returns-argument=@dynamic:1,returns=@static:4,returns-argument=@tied:1,returns-argument=@buffer:1 -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --canonicalize --idr-expect=holds=returns-argument=@untied:1 -o /dev/null 2> %t.err
// RUN: FileCheck %s --check-prefix=UNTIED < %t.err
// RUN: idris-mlir-opt %s --canonicalize -o %t.folded.mlir
// RUN: %differential %s %t.folded.mlir
// An array tied to sizes has those sizes as its dimensions: the dimension
// of a tied tensor or buffer at a dynamic dimension folds to the size it
// was tied to, and at a static one to the constant of its type, through
// the dialect's canonicalization of shaped results. So a size Idris proved
// equal across a call is the same value on both sides, and no dimension is
// read at run time. An array tied to nothing keeps its dimension a read
// (@untied). The patterns converge (the first RUN line). The root ties
// arrays of 0 to 4 elements, as many as the input byte says, to their
// sizes and prints each dimension the functions read: folded, the program
// prints what the one as written printed, on every byte.
// UNTIED: expected returns-argument: {{.*}}@untied
idr.program @"dims-fold" root(@root) stage(first) {
  idr.func @dynamic(%x: tensor<?xi64>, %n: index) -> index {
    %y = idr.tie_shape %x dims(%n) : tensor<?xi64>
    %c0 = arith.constant 0 : index
    %d = tensor.dim %y, %c0 : tensor<?xi64>
    return %d : index
  }
  idr.func @static(%x: tensor<4x?xi64>, %m: index) -> index {
    %y = idr.tie_shape %x dims(%m) : tensor<4x?xi64>
    %c0 = arith.constant 0 : index
    %d0 = tensor.dim %y, %c0 : tensor<4x?xi64>
    return %d0 : index
  }
  idr.func @tied(%x: tensor<4x?xi64>, %m: index) -> index {
    %y = idr.tie_shape %x dims(%m) : tensor<4x?xi64>
    %c1 = arith.constant 1 : index
    %d1 = tensor.dim %y, %c1 : tensor<4x?xi64>
    return %d1 : index
  }
  idr.func @untied(%x: tensor<?xi64>, %n: index) -> index {
    %c0 = arith.constant 0 : index
    %d = tensor.dim %x, %c0 : tensor<?xi64>
    return %d : index
  }
  idr.func @buffer(%b: memref<?xf64>, %k: index) -> index {
    %y = idr.tie_shape %b dims(%k) : memref<?xf64>
    %c0 = arith.constant 0 : index
    %d = memref.dim %y, %c0 : memref<?xf64>
    return %d : index
  }
  idr.func @root(%w: !idr.world) -> !idr.world {
    %ch, %w0 = idr.io.get_byte %w
    %b = arith.extui %ch : i32 to i64
    %c5 = arith.constant 5 : i64
    %k = arith.remui %b, %c5 : i64
    %n = arith.index_cast %k : i64 to index
    %x = idr.tabulate [%n] {
    ^bb0(%i: index):
      %e = arith.index_cast %i : index to i64
      idr.array.yield %e : i64
    } : tensor<?xi64>
    %y = idr.tabulate [%n] {
    ^bb0(%i: index, %j: index):
      %e = arith.index_cast %j : index to i64
      idr.array.yield %e : i64
    } : tensor<4x?xi64>
    %m = memref.alloc(%n) : memref<?xf64>
    %d1 = idr.call @dynamic(%x, %n) : (tensor<?xi64>, index) -> index
    %d2 = idr.call @static(%y, %n) : (tensor<4x?xi64>, index) -> index
    %d3 = idr.call @tied(%y, %n) : (tensor<4x?xi64>, index) -> index
    %d4 = idr.call @untied(%x, %n) : (tensor<?xi64>, index) -> index
    %d5 = idr.call @buffer(%m, %n) : (memref<?xf64>, index) -> index
    %e1 = arith.index_cast %d1 : index to i64
    %e2 = arith.index_cast %d2 : index to i64
    %e3 = arith.index_cast %d3 : index to i64
    %e4 = arith.index_cast %d4 : index to i64
    %e5 = arith.index_cast %d5 : index to i64
    %w1 = idr.io.put_sint %e1, %w0 : i64
    %w2 = idr.io.put_sint %e2, %w1 : i64
    %w3 = idr.io.put_sint %e3, %w2 : i64
    %w4 = idr.io.put_sint %e4, %w3 : i64
    %w5 = idr.io.put_sint %e5, %w4 : i64
    return %w5 : !idr.world
  }
}
