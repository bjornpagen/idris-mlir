// NEEDS-ACCEPTANCE: --runtime-bitcode-section is no option of idris-mlir: exit 2, LLVM's unknown-argument error, no object; where the prepared runtime keeps its bitcode is the target entry's, and a compilation reads it off the runtime.
// RUN: %status 2 idris-mlir -c %s -o %t.o --runtime-bitcode-section= 2> %t.err
// RUN: FileCheck %s < %t.err
// RUN: test ! -e %t.o
// CHECK: Unknown command line argument '--runtime-bitcode-section='
idr.program @"bitcode-section-option" root(@Prog.main) stage(higher) {
  idr.func @Prog.main() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}
