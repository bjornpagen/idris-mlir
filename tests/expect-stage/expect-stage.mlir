// RUN: idris-mlir-opt %s --idr-expect=holds=stage=first -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=stage=owned -verify-diagnostics -o /dev/null
// The stage is the program's, said once by its idr.program: this one is
// at the first stage, not the owned one.
// expected-error @below {{expected stage: }}
idr.program @stage root(@root) stage(first) {
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
