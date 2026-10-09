// RUN: %status 2 idris-mlir %s -p base -o %t 2> %t.p.err
// RUN: FileCheck --check-prefix=FRONT %s < %t.p.err
// RUN: %status 2 idris-mlir %s -o %s 2> %t.same.err
// RUN: FileCheck --check-prefix=SAME %s < %t.same.err
// RUN: idris-mlir-opt %s --emit-bytecode -o %t.mlirbc
// RUN: idris-mlir -c %t.mlirbc -o %t.bc.o
// RUN: test -s %t.bc.o
// A module is an input with MLIR's extension, text or bytecode; any other
// is Idris source. The frontend's options are for Idris source only, and
// an -o that names the input (or makes outputs that collide) is a usage
// error, which leaves every file as it was.
// FRONT: idris-mlir: {{.*}}the frontend's, for Idris source
// SAME: idris-mlir: -o names outputs that collide
module attributes {idr.program} {
  func.func @Prog.main() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}
