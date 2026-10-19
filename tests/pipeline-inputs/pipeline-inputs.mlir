// RUN: %status 2 idris-mlir %s -p base -o %t 2> %t.p.err
// RUN: FileCheck --check-prefix=FRONT %s < %t.p.err
// RUN: cp %s %t.input.mlir
// RUN: %status 2 idris-mlir %t.input.mlir -o %t.input.mlir 2> %t.same.err
// RUN: FileCheck --check-prefix=SAME %s < %t.same.err
// RUN: cmp %s %t.input.mlir
// RUN: %status 2 idris-mlir -c %s -o %t.both --report=%t.both 2> %t.both.err
// RUN: FileCheck --check-prefix=SAME %s < %t.both.err
// RUN: test ! -e %t.both
// RUN: idris-mlir-opt %s --emit-bytecode -o %t.mlirbc
// RUN: idris-mlir -c %t.mlirbc -o %t.bc.o
// RUN: test -s %t.bc.o
// A module is an input with MLIR's extension, text or bytecode; any other
// is Idris source. The frontend's options are for Idris source only, and
// an -o that names the input (or makes outputs that collide) is a usage
// error, which leaves every file as it was: the input, which a copy of it
// shows unchanged, and the output, which -o and --report both name and
// neither writes.
// FRONT: idris-mlir: {{.*}}the frontend's, for Idris source
// SAME: idris-mlir: -o and --report name outputs that collide
idr.program @inputs root(@Prog.main) stage(higher) {
  idr.func @Prog.main() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}
