// NEEDS-ACCEPTANCE: that idr-optimize reports its inner canonicalize's and cse's counts, and that the inner cse merged the two equal products.
// RUN: idris-mlir-opt %s --idr-optimize -mlir-pass-statistics -mlir-pass-statistics-display=list -o /dev/null 2> %t.stats
// RUN: FileCheck %s < %t.stats
// The steps of idr-optimize's inner pipeline run on copies of it that
// no pass manager reports; idr-optimize adds their counts to its own.
// CHECK-DAG: idr-canonicalize.not-converged
// CHECK-DAG: {{[1-9][0-9]*}} cse.num-cse'd
// CHECK-DAG: cse.num-dce'd
idr.program @stats root(@main) stage(first) {
  idr.func @main(%x: i64) -> i64 attributes {total} {
    %a = arith.muli %x, %x : i64
    %b = arith.muli %x, %x : i64
    %c = arith.addi %a, %b : i64
    return %c : i64
  }
}
