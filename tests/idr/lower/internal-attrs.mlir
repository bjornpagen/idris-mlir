// RUN: idris-mlir-opt %s --idr-lower --canonicalize --cse --convert-scf-to-cf --convert-to-llvm --reconcile-unrealized-casts > %t.mlir
// RUN: FileCheck %s < %t.mlir
// The attributes idr-specialize keeps on a clone (its key, its origin and
// the holes its parameters hold): idr-lower drops them with the rest of the
// idr attributes, so what LLVM gets carries none.
// CHECK-LABEL: llvm.func @f(
// CHECK-LABEL: llvm.func @g(
// CHECK: llvm.call @f(
// CHECK-NOT: idr.
module attributes {idr.program} {
  func.func private @f(%a: i64 {idr.hole = 0 : i64}) -> i64 attributes {idr.total, idr.origin = "g", idr.spec_key = #idr.key_apply<"g", 1>} {
    return %a : i64
  }
  func.func private @g(%x: i64) -> i64 attributes {idr.total} {
    %r = func.call @f(%x) : (i64) -> i64
    return %r : i64
  }
  func.func @Main.main() -> i64 {
    %c = arith.constant 3 : i64
    %r = func.call @g(%c) : (i64) -> i64
    return %r : i64
  }
}
