// RUN: idris-mlir-opt %s --idr-lower --canonicalize --cse --convert-scf-to-cf --convert-to-llvm --reconcile-unrealized-casts > %t.mlir
// RUN: FileCheck %s --implicit-check-not=instance --implicit-check-not=total --implicit-check-not=no_inline < %t.mlir
// The facts of an idr.func (what Idris proved, total; what the frontend
// decided, instance and no_inline): idr-lower reads what LLVM needs from
// them and keeps none, so what LLVM gets carries no idr attribute.
// CHECK-LABEL: llvm.func @f(
// CHECK-LABEL: llvm.func @g(
// CHECK: llvm.call @f(
// CHECK-NOT: idr.
module {
  idr.func private @f(%a: i64) -> i64 attributes {total, no_inline, instance = #idr.instance<"Main.f", []>} {
    return %a : i64
  }
  idr.func private @g(%x: i64) -> i64 attributes {total} {
    %r = idr.call @f(%x) : (i64) -> i64
    return %r : i64
  }
  idr.func @Main.main() -> i64 {
    %c = arith.constant 3 : i64
    %r = idr.call @g(%c) : (i64) -> i64
    return %r : i64
  }
}
