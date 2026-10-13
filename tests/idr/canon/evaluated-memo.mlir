// RUN: idris-mlir-opt %s --idr-defunctionalize > %t.mlir
// RUN: FileCheck %s --implicit-check-not='{{(idr\.| )delay }}' < %t.mlir
// RUN: idris-mlir-opt %s --canonicalize=test-convergence=true -o /dev/null
// An evaluated suspension is a cell already forced. Its key has a memo sum
// like any lazy key, with no label of its own, and the delay becomes the
// sum's `forced` constructor holding the value; the force keeps its op and
// reads the box.
// CHECK: idr.data @[[L:lazy\$[0-9]+]] box memo
// CHECK-NOT: idr.ctor @{{.*}}.delay
// CHECK: idr.ctor @running ()
// CHECK-NEXT: idr.ctor @forced (i64)
// CHECK-LABEL: idr.func @Main.main(
// CHECK: %[[C:.*]] = {{(idr\.)?}}con @[[L]]::@forced(%{{.*}}) : (i64) -> ![[L]]
// CHECK: force %[[C]] : ![[L]] -> i64
module attributes {idr.program} {
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %t = idr.delay : !idr.lazy<i64> {
      idr.yield %n : i64
    }
    %v = idr.force %t : !idr.lazy<i64> -> i64
    %w2 = idr.io.put_int signed %v, %w1 : i64
    return %w2 : !idr.world
  }
}
