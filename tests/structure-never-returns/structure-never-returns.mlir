// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr.func(idr-structure-loops)))' -o %t.mlir
// RUN: %differential %s %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=counted-loop=@gen,crash-sites=@gen:1 -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=counted-loop=@gen -o /dev/null
// A tabulation whose region never returns ends in its crash, and its
// region's terminator is ub.unreachable: no element is ever made, and no
// value stands for one. The crash is the program's at the first index,
// never the compiler's error, and it is kept where the op is lowered: a
// counted loop, which no tabulation was before the pass, and no linalg
// op, since no element is ever made. The root makes 0 to 2 elements, as
// the input byte sets: an empty domain makes none and so does not crash,
// and prints its size, 0; any other crashes before it prints. The lowered
// program does the same on every byte.
idr.program @"never-returns" root(@root) stage(first) types #idr.types<> {
  idr.func @gen(%n: index) -> tensor<?xi64> {
    %t = idr.tabulate [%n] {
    ^bb0(%i: index):
      idr.crash "boom"
      ub.unreachable
    } : tensor<?xi64>
    return %t : tensor<?xi64>
  }
  idr.func @root(%w: !idr.world) -> !idr.world {
    %ch, %w0 = idr.io.get_byte %w
    %b = arith.extui %ch : i32 to i64
    %c3 = arith.constant 3 : i64
    %k = arith.remui %b, %c3 : i64
    %n = arith.index_cast %k : i64 to index
    %t = idr.call @gen(%n) : (index) -> tensor<?xi64>
    %c0 = arith.constant 0 : index
    %size = tensor.dim %t, %c0 : tensor<?xi64>
    %s = arith.index_cast %size : index to i64
    %w1 = idr.io.put_sint %s, %w0 : i64
    return %w1 : !idr.world
  }
}
