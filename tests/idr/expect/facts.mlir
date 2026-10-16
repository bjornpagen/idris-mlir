// NEEDS-ACCEPTANCE: that facts-as-marked holds of the module pulled out of the CLEAN lines and fails once, at the idr.io.put_str marked as one that may be dropped.
// RUN: sed -n 's|^// CLEAN: ||p' %s > %t.clean.mlir
// RUN: idris-mlir-opt %t.clean.mlir --idr-expect=holds=facts-as-marked -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=facts-as-marked -o /dev/null 2> %t.err
// RUN: FileCheck %s < %t.err
// RUN: grep 'error: expected ' %t.err | count 1
// An op marked with what the dialect answers about it holds (an output,
// which may be neither dropped, moved, delayed nor merged: the CLEAN
// module); one marked with an answer the dialect does not give fails.
// CHECK-DAG: error: expected facts-as-marked: in @root, {{.*}} answers "{{.*}}", not "{{.*}}"
// CLEAN: idr.program @clean root(@root) stage(first) {
// CLEAN:   idr.func @root(%w: !idr.world) -> !idr.world {
// CLEAN:     %c = arith.constant 65 : i32
// CLEAN:     %w1 = idr.io.put_char %c, %w {expect.facts = ""}
// CLEAN:     return %w1 : !idr.world
// CLEAN:   }
// CLEAN: }
idr.program @facts root(@root) stage(first) {
  idr.func @root(%w: !idr.world) -> !idr.world {
    %s = idr.constant "hi" : !idr.str
    %w1 = idr.io.put_str %s, %w {expect.facts = "drop"}
    return %w1 : !idr.world
  }
}
