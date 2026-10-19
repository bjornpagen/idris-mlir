// RUN: idris-mlir-opt %s --idr-expect=holds=stage=first -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=stage=higher,stage=graded,stage=owned,stage=lowered -verify-diagnostics -o /dev/null
// The stage is the program's, said once by its idr.program: this one is
// at the first stage, and at none of the others, the one before it and
// the three after it.
// expected-error @below {{expected stage: the program is at stage first, not higher}}
// expected-error @below {{expected stage: the program is at stage first, not graded}}
// expected-error @below {{expected stage: the program is at stage first, not owned}}
// expected-error @below {{expected stage: the program is at stage first, not lowered}}
idr.program @stage root(@root) stage(first) {
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
