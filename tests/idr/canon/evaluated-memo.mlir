// RUN: idris-mlir-opt %s --idr-defunctionalize > %t.mlir
// RUN: FileCheck %s --implicit-check-not='{{(idr\.| )delay }}' < %t.mlir
// RUN: idris-mlir-opt %s --canonicalize=test-convergence=true -o /dev/null
// NEEDS-ACCEPTANCE: the memo sum's spelling as C01 prints an identified type, and its constructor names, as C06 makes them.
// An evaluated suspension, `idr.delay %value`, is a cell already forced.
// Its key has a memo sum like any lazy key, with no label of its own, and
// the delay becomes the sum's `forced` constructor holding the value; the
// force keeps its op and reads the box.
// CHECK: ![[L:[A-Za-z_][A-Za-z0-9_.$]*]] = !idr.data<"{{[^"]*}}", memo [@running(), @forced(i64)]>
// CHECK-LABEL: idr.func @Main.main(
// CHECK: %[[C:.*]] = {{(idr\.)?}}con @forced(%{{.*}}) : (i64) -> !idr.box<![[L]]>
// CHECK: force %[[C]] : !idr.box<![[L]]> -> i64
module {
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %t = idr.delay %n : i64 -> !idr.lazy<i64>
    %v = idr.force %t : !idr.lazy<i64> -> i64
    %w2 = idr.io.put_int signed %v, %w1 : i64
    return %w2 : !idr.world
  }
}
