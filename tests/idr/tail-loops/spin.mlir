// RUN: idris-mlir-opt %s --idr-tail-loops --canonicalize --cse | FileCheck %s
// rule: LOW-TAIL-4, SEM-EVAL-5, OPT-SAFE-1
// A loop that never ends and has no effect is not deleted by the generic passes.
module attributes {idr.version = 0 : i64, idr.entry = @r, idr.entry_kind = "int"} {
  // CHECK-LABEL: func.func private @spin(
  // CHECK: scf.while
  // CHECK: idr.may_loop
  func.func private @spin(%n: i64 {idr.quantity = "w"}) -> i64 attributes {idr.name = "spin"} {
    %r = func.call @spin(%n) : (i64) -> i64
    return %r : i64
  }
  func.func private @r() -> i64 attributes {idr.name = "r"} {
    %c = arith.constant 1 : i64
    %s = func.call @spin(%c) : (i64) -> i64
    return %s : i64
  }
}
