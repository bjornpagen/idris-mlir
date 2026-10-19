// RUN: %status 2 idris-mlir --print-target-triple -c 2> %t.err
// RUN: FileCheck %s < %t.err
// RUN: %status 2 idris-mlir --print-runtime -c 2> %t.runtime.err
// RUN: FileCheck %s < %t.runtime.err
// RUN: %status 2 idris-mlir --print-link-flags -c 2> %t.flags.err
// RUN: FileCheck %s < %t.flags.err
// RUN: %status 2 idris-mlir --print-target-triple -o %t.printed 2> %t.output.err
// RUN: FileCheck %s --check-prefix=OUTPUT < %t.output.err
// RUN: test ! -e %t.printed
// RUN: %status 2 idris-mlir --prepare-runtime -o %t.o -c 2> %t.prepare.err
// RUN: FileCheck %s --check-prefix=PREPARE < %t.prepare.err
// RUN: test ! -e %t.o
// RUN: idris-mlir --print-target-triple > %t.triple
// RUN: test -s %t.triple
// Each action reads its own options and no other of the driver's: one
// given to an action that does not read it is refused, not ignored: -c by
// each --print action, and -o by one, which writes nothing there.
// CHECK: idris-mlir: a --print option takes no -c
// PREPARE: idris-mlir: --prepare-runtime takes no -c
// OUTPUT: idris-mlir: a --print option takes no -o
idr.program @"print-with-object" root(@Prog.main) stage(higher) {
  idr.func @Prog.main() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}
