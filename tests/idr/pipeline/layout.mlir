// RUN: idris-mlir-cc %s -o %t.s --emit=asm
// RUN: FileCheck %s < %t.s
// rule: OPT-PIPE-4
// Functions start on a 64-byte line (.p2align 6). The root is private and
// inlined into the generated main (LOW-ENTRY-1), which is what remains.
// CHECK: .p2align 6
// CHECK-NEXT: .type main,@function
module attributes {idr.program} {
  func.func @Prog.main() -> i64 {
    %c = arith.constant 42 : i64
    return %c : i64
  }
}
