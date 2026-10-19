// RUN: %status 2 idris-mlir -c %s -o %t.o -mlir-print-ir-after=gpu-kernel-outlining 2> %t.err
// RUN: FileCheck %s < %t.err
// RUN: test ! -e %t.o
// The compiler registers the dialects, extensions and passes it runs, and
// nothing else, so an option that names a pass names one of those.
// CHECK: gpu-kernel-outlining
idr.program @"foreign-pass-name" root(@Prog.main) stage(higher) {
  idr.func @Prog.main() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}
