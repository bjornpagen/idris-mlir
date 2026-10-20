// RUN: %status 2 idris-mlir -c %s
// RUN: printf old > %t.stale
// RUN: cp %t.stale %t.usage.o
// RUN: %status 2 idris-mlir --no-such-option -c %s -o %t.usage.o 2> %t.usage.err
// RUN: FileCheck %s --check-prefix=USAGE < %t.usage.err
// RUN: cmp %t.usage.o %t.stale
// RUN: sed -n 's|^// INPUT: ||p' %s > %t.foreign.mlir
// RUN: %status 1 idris-mlir -c %t.foreign.mlir -o %t.o 2> %t.err
// RUN: FileCheck %s --check-prefix=FOREIGN < %t.err
// RUN: not ls %t.o
// RUN: cp %t.stale %t.keep.o
// RUN: %status 1 idris-mlir -c %t.foreign.mlir -o %t.keep.o 2> %t.keep.err
// RUN: FileCheck %s --check-prefix=FOREIGN < %t.keep.err
// RUN: not ls %t.keep.o
// RUN: cp %t.stale %t.fresh.o
// RUN: idris-mlir -c %s -o %t.fresh.o
// RUN: not cmp -s %t.fresh.o %t.stale
// RUN: %cc %t.fresh.o -o %t.fresh
// RUN: %t.fresh
// Usage errors are status 2: no -o, an option idris-mlir does not have;
// and a usage error, found before anything runs, leaves every file as it
// was, a stale output included. A module that holds an idr.program holds
// only the dialects the frontend writes, so an op of any other (here cf)
// is refused: status 1, and no output. A failed compilation leaves none of
// its outputs, a stale one from an earlier compilation included; a
// compilation that succeeds replaces it with its own, which links and runs.
// USAGE: no-such-option
// FOREIGN: error: 'cf.assert' op
// INPUT: idr.program @foreign root(@Prog.main) stage(higher) types #idr.types<> {
// INPUT:   idr.func @Prog.main() -> i64 {
// INPUT:     %z = arith.constant 0 : i64
// INPUT:     %t = arith.constant true
// INPUT:     cf.assert %t, "never"
// INPUT:     return %z : i64
// INPUT:   }
// INPUT: }
idr.program @statuses root(@Prog.main) stage(higher) types #idr.types<> {
  idr.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}
