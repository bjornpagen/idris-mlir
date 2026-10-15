// RUN: idris-mlir-opt %s --idr-defunctionalize -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=builds=@Main.main,forces-nothing=@Main.main,no-closures -o /dev/null
// RUN: FileCheck %s < %t.mlir
// RUN: idris-mlir-opt %s --idr-canonicalize=test-convergence=true -o /dev/null
// NEEDS-ACCEPTANCE: the memo sum's printed body, an identified type with its roles, and that the force became a call of the sum's dispatch, so no force is left.
// An evaluated suspension, `idr.delay %value`, is a cell already forced.
// Its key has a memo sum like any lazy key, with no label of its own, and
// the delay becomes the sum's forced constructor holding the value, built
// at run time; the force is a call of the sum's dispatch, which reads the
// cell, so no force is left, and no suspension type either (the program's
// stage is first). The sum's body is how it prints.
// CHECK: = !idr.data<"{{[^"]*}}", memo [@running() running, @forced(i64) forced]>
idr.program @"evaluated-memo" root(@Main.main) stage(higher) {
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %t = idr.delay %n : i64 -> !idr.lazy<i64>
    %v = idr.force %t : !idr.lazy<i64> -> i64
    %w2 = idr.io.put_int signed %v, %w1 : i64
    return %w2 : !idr.world
  }
}
