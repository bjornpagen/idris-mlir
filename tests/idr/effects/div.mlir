// RUN: idris-mlir-opt %s --canonicalize --cse --loop-invariant-code-motion | FileCheck %s
// rule: IDR-EFF-1, OPT-SAFE-1, SEM-EVAL-4
module attributes {idr.version = 0 : i64, idr.entry = @r, idr.entry_kind = "int"} {
  // A dead division by a value that may be zero stays, because it may crash;
  // a dead division by a nonzero constant is removed.
  // CHECK-LABEL: func.func @dead(
  // CHECK-SAME: %[[X:.*]]: i64, %[[Y:.*]]: i64)
  // CHECK-NEXT: idr.div signed %[[X]], %[[Y]] : i64
  // CHECK-NEXT: return %[[X]]
  func.func @dead(%x: i64, %y: i64) -> i64 {
    %c3 = arith.constant 3 : i64
    %q = idr.div signed %x, %y : i64
    %s = idr.div signed %x, %c3 : i64
    return %x : i64
  }
  // A division that may crash is not speculated out of a branch.
  // CHECK-LABEL: func.func @guarded(
  // CHECK: scf.if
  // CHECK-NEXT: idr.div signed
  func.func @guarded(%b: i1, %x: i64, %y: i64) -> i64 {
    %r = scf.if %b -> i64 {
      %q = idr.div signed %x, %y : i64
      scf.yield %q : i64
    } else {
      scf.yield %x : i64
    }
    return %r : i64
  }
  func.func private @r() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}
