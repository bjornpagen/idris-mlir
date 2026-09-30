// RUN: idris-mlir-cc %s -o %t.s --emit=asm
// RUN: awk '/[.]type.*,@function$/ && prev !~ /[.]p2align\t6$/ { bad = 1 } { prev = $0 } END { exit bad }' %t.s
// RUN: FileCheck %s < %t.s
// Every function starts on a 64-byte line (.p2align 6), main among them.
// CHECK: .type main,@function
module attributes {idr.program} {
  func.func @Prog.main() -> i64 {
    %c = arith.constant 42 : i64
    return %c : i64
  }
}
