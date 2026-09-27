// RUN: rm -rf %t.dir && mkdir -p %t.dir
// RUN: idris-mlir-cc %s -o %t.o --dump-after=all --dump-dir=%t.dir
// RUN: ls %t.dir | FileCheck %s
// rule: OPT-PIPE-1, DRV-CC-1, LOW-TARGET-1
// CHECK: 01-idr-check-input.mlir
// CHECK-NEXT: 02-idr-entry.mlir
// CHECK-NEXT: 03-inline.mlir
// CHECK-NEXT: 04-sccp.mlir
// CHECK-NEXT: 05-canonicalize.mlir
// CHECK-NEXT: 06-cse.mlir
// CHECK-NEXT: 07-symbol-dce.mlir
// CHECK-NEXT: 08-idr-lower.mlir
module attributes {idr.version = 0 : i64, idr.entry = @Prog.main, idr.entry_kind = "int"} {
  func.func private @Prog.main() -> i64 attributes {idr.name = "main"} {
    %c = arith.constant 42 : i64
    return %c : i64
  }
}
