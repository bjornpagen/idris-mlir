// RUN: %status 2 idris-mlir-cc %s
// RUN: sed -n 's|^// INPUT: ||p' %s > %t.foreign.mlir
// RUN: %status 1 idris-mlir-cc %t.foreign.mlir -o %t.o 2> %t.err
// RUN: FileCheck %s --check-prefix=FOREIGN < %t.err
// RUN: not ls %t.o
// RUN: printf old > %t.keep.o
// RUN: %status 1 idris-mlir-cc %t.foreign.mlir -o %t.keep.o
// RUN: grep -qx old %t.keep.o
// Usage errors are status 2: no -o. The program is parsed with exactly the
// contract's dialects, so an op of any other (here scf) fails to parse:
// status 1, and no output; an output file that already exists is left
// untouched.
// FOREIGN: error: {{.*}}scf.execute_region
// INPUT: module attributes {idr.program} {
// INPUT:   func.func @Prog.main() -> i64 {
// INPUT:     %r = scf.execute_region -> i64 {
// INPUT:       %z = arith.constant 0 : i64
// INPUT:       scf.yield %z : i64
// INPUT:     }
// INPUT:     return %r : i64
// INPUT:   }
// INPUT: }
module attributes {idr.program} {
  func.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}
