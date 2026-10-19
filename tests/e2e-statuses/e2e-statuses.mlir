// RUN: %status 2 idris-mlir -c %s
// RUN: sed -n 's|^// INPUT: ||p' %s > %t.foreign.mlir
// RUN: %status 1 idris-mlir -c %t.foreign.mlir -o %t.o 2> %t.err
// RUN: FileCheck %s --check-prefix=FOREIGN < %t.err
// RUN: not ls %t.o
// RUN: printf old > %t.keep.o
// RUN: %status 1 idris-mlir -c %t.foreign.mlir -o %t.keep.o 2> %t.keep.err
// RUN: FileCheck %s --check-prefix=FOREIGN < %t.keep.err
// RUN: not ls %t.keep.o
// Usage errors are status 2: no -o. A module that holds an idr.program
// holds only the dialects the frontend writes, so an op of any other (here
// cf) is refused: status 1, and no output. A failed compilation leaves none of its
// outputs, a stale one from an earlier compilation included.
// FOREIGN: error: 'cf.assert' op
// INPUT: idr.program @foreign root(@Prog.main) stage(higher) {
// INPUT:   idr.func @Prog.main() -> i64 {
// INPUT:     %z = arith.constant 0 : i64
// INPUT:     %t = arith.constant true
// INPUT:     cf.assert %t, "never"
// INPUT:     return %z : i64
// INPUT:   }
// INPUT: }
idr.program @statuses root(@Prog.main) stage(higher) {
  idr.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}
