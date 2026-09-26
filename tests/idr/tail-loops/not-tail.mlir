// RUN: idris-mlir-opt %s --idr-tail-loops | FileCheck %s
// rule: LOW-TAIL-3
// A self call whose result is used is not a tail call: no loop.
module attributes {idr.version = 0 : i64, idr.entry = @r, idr.entry_kind = "int"} {
  // CHECK-LABEL: func.func private @fact(
  // CHECK-NOT: scf.while
  // CHECK: call @fact
  func.func private @fact(%n: i64 {idr.quantity = "w"}) -> i64 attributes {idr.name = "fact"} {
    %c0 = arith.constant 0 : i64
    %c1 = arith.constant 1 : i64
    %z = arith.cmpi eq, %n, %c0 : i64
    %r = scf.if %z -> i64 {
      scf.yield %c1 : i64
    } else {
      %m = arith.subi %n, %c1 : i64
      %t = func.call @fact(%m) : (i64) -> i64
      %p = arith.muli %n, %t : i64
      scf.yield %p : i64
    }
    return %r : i64
  }
  func.func private @r() -> i64 attributes {idr.name = "r"} {
    %c = arith.constant 5 : i64
    %s = func.call @fact(%c) : (i64) -> i64
    return %s : i64
  }
}
