// RUN: idris-mlir-opt %s --idr-lower --canonicalize --cse --convert-scf-to-cf --convert-to-llvm --reconcile-unrealized-casts > %t.mlir
// RUN: FileCheck %s < %t.mlir
// rule: LOW-UP-1, ELIM-SPEC-1, ELIM-G-5
// The attributes idr-specialize keeps between rounds sit on calls too (the
// history of a clone's calls, a stopped call): idr-lower drops them with
// the rest of the idr attributes, so the calls LLVM gets carry none.
// CHECK-LABEL: llvm.func @f(
// CHECK-LABEL: llvm.func @g(
// CHECK: llvm.call @f(
// CHECK-NOT: idr.
module attributes {idr.program, idr.clone_counts = {f = 1 : i64}} {
  func.func private @f(%a: i64 {idr.quantity = "w", idr.hole = 0 : i64}) -> i64 attributes {idr.total, idr.origin = "g", idr.spec_key = "[unit]"} {
    return %a : i64
  }
  func.func private @g(%x: i64 {idr.quantity = "w"}) -> i64 attributes {idr.total} {
    %r = func.call @f(%x) {idr.spec_caller = {g = "[unit]"}, idr.spec_stopped, idr.spec_stopped_at = "[unit]"} : (i64) -> i64
    return %r : i64
  }
  func.func @Main.main() -> i64 {
    %c = arith.constant 3 : i64
    %r = func.call @g(%c) : (i64) -> i64
    return %r : i64
  }
}
