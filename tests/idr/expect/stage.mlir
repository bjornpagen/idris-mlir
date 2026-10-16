// NEEDS-ACCEPTANCE: that stage holds of the stage the program says and fails once, at the program, for another.
// RUN: idris-mlir-opt %s --idr-expect=holds=stage=first -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=stage=owned -o /dev/null 2> %t.err
// RUN: FileCheck %s < %t.err
// RUN: grep 'error: expected ' %t.err | count 1
// The stage is the program's, said once by its idr.program: this one is
// at the first stage, not the owned one.
// CHECK-DAG: error: expected stage: the program is at stage {{.*}}, not {{.*}}
idr.program @stage root(@root) stage(first) {
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
