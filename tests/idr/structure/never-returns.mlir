// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr.func(idr-structure-loops)))' -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=structured-loops=@gen,crash-sites=@gen:1 -o /dev/null
// NEEDS-ACCEPTANCE: a region ending in ub.unreachable lowered by idr-structure-loops (R10, B15).
// A tabulation whose region never returns ends in its crash, and its
// region's terminator is ub.unreachable: no element is ever made, and no
// value stands for one. The crash is the program's at the first index,
// never the compiler's error, and it is kept where the op is lowered.
idr.program @"never-returns" root(@root) stage(first) {
  idr.func @gen(%n: index) -> tensor<?xi64> {
    %t = idr.tabulate [%n] {
    ^bb0(%i: index):
      idr.crash "boom"
      ub.unreachable
    } : tensor<?xi64>
    return %t : tensor<?xi64>
  }
  idr.func @root() -> i64 {
    %c0 = arith.constant 0 : index
    %c4 = arith.constant 4 : index
    %t = idr.call @gen(%c4) : (index) -> tensor<?xi64>
    %v = tensor.extract %t[%c0] : tensor<?xi64>
    return %v : i64
  }
}
