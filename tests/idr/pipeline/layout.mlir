// RUN: idris-mlir -c %s -o %t.o
// RUN: llvm-nm --defined-only --radix=d %t.o > %t.symbols
// RUN: awk '$2 ~ /^[Tt]$/ && $1 % 64 { bad = 1 } END { exit bad }' %t.symbols
// RUN: FileCheck %s < %t.symbols
// Every function starts on a 64-byte line, main among them: each function
// symbol's address in the object is a multiple of 64, on ELF and Mach-O.
// CHECK: {{[Tt] _?main$}}
module attributes {idr.program} {
  func.func @Prog.main() -> i64 {
    %c = arith.constant 42 : i64
    return %c : i64
  }
}
