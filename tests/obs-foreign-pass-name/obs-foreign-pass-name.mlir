// RUN: %status 2 idris-mlir -c %s -o %t.o -mlir-print-ir-after=gpu-kernel-outlining 2> %t.err
// RUN: FileCheck %s < %t.err
// RUN: test ! -e %t.o
// RUN: idris-mlir -c %s -o %t.ok.o -mlir-print-ir-after=idr-optimize 2> %t.ok.err
// RUN: test -s %t.ok.o
// RUN: test -s %t.ok.err
// The compiler registers the dialects, extensions and passes it runs, and
// nothing else, so an option that names a pass names one of those: the
// option naming one it runs, idr-optimize, prints the module after it, and
// the object is written.
// CHECK: gpu-kernel-outlining
idr.program @"foreign-pass-name" root(@Prog.main) stage(higher) types #idr.types<> {
  idr.func @Prog.main() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}
