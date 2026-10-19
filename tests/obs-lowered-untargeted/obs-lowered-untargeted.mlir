// RUN: sed -n 's|^// UNTARGETED: ||p' %s > %t.untargeted.mlir
// RUN: %status 1 idris-mlir -c %t.untargeted.mlir -o %t.o --report=%t.report 2> %t.err
// RUN: FileCheck %s < %t.err
// RUN: FileCheck %s --check-prefix=REPORT < %t.report
// RUN: test ! -e %t.o
// The pipeline's output names the target it is compiled for, which a
// module of the LLVM dialect alone must, for the build's triple: one that
// names none is the input's fault, said at the module when its kind is
// read.
// CHECK: error: {{.*}}#llvm.target
// REPORT: verdict: internal
// UNTARGETED: llvm.func @main() -> i64 {
// UNTARGETED:   %c = llvm.mlir.constant(42 : i64) : i64
// UNTARGETED:   llvm.return %c : i64
// UNTARGETED: }
idr.program @"lowered-untargeted" root(@Prog.main) stage(higher) {
  idr.func @Prog.main() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}
