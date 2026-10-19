// RUN: sed -n 's|^// UNTARGETED: ||p' %s > %t.untargeted.mlir
// RUN: %status 1 idris-mlir -c %t.untargeted.mlir -o %t.o --report=%t.report 2> %t.err
// RUN: FileCheck %s < %t.err
// RUN: FileCheck %s --check-prefix=REPORT < %t.report
// RUN: test ! -e %t.o
// RUN: idris-mlir-opt %t.untargeted.mlir --idr-target -o %t.targeted.mlir
// RUN: idris-mlir -c %t.targeted.mlir -o %t.targeted.o
// RUN: %cc %t.targeted.o -o %t.targeted
// RUN: %status 42 %t.targeted
// The pipeline's output names the target it is compiled for, which a
// module of the LLVM dialect alone must, for the build's triple: one that
// names none is the input's fault, said at the module when its kind is
// read. The target is all it lacks: the same module given the build's
// (--idr-target) compiles, links and exits with its 42.
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
