// RUN: idris-mlir-cc %s -o %t.s --emit=asm
// RUN: FileCheck %s < %t.s
// rule: OPT-PIPE-4
// Functions start on a 64-byte line (.p2align 6).
// CHECK: .p2align 6
// CHECK-NEXT: .type Prog.main,@function
module attributes {idr.version = 0 : i64, idr.entry = @Prog.main, idr.entry_kind = "int"} {
  func.func private @Prog.main() -> i64 {
    %c = arith.constant 42 : i64
    return %c : i64
  }
}
