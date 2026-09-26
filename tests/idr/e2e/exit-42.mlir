// RUN: idris-mlir-cc %s -o %t.o
// RUN: %cc %t.o -o %t
// RUN: %status 42 %t
// p0 exit criterion: a hand-written func/arith module becomes an executable.
// rule: DRV-CC-1
module attributes {idr.version = 0 : i64, idr.entry = @Prog.main, idr.entry_kind = "int"} {
  func.func private @Prog.main() -> i64 attributes {idr.name = "main"} {
    %a = arith.constant 40 : i64
    %b = arith.constant 2 : i64
    %c = arith.addi %a, %b : i64
    return %c : i64
  }
}
