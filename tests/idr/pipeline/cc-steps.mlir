// RUN: rm -rf %t.dir && mkdir -p %t.dir
// RUN: idris-mlir-cc %s -o %t.o --dump-after=all --dump-dir=%t.dir
// RUN: ls %t.dir | FileCheck %s
// RUN: idris-mlir-opt %s --idr-pipeline -o %t.p.mlir
// CHECK: 01-idr-simplify.mlir
// CHECK-NEXT: 02-idr-defunctionalize.mlir
// CHECK-NEXT: 03-canonicalize.mlir
// CHECK-NEXT: 04-idr-tail-loops.mlir
// CHECK-NEXT: 05-idr-check-profile.mlir
// CHECK-NEXT: 06-idr-lower.mlir
module attributes {idr.program} {
  func.func @Prog.main() -> i64 {
    %c = arith.constant 42 : i64
    return %c : i64
  }
}
