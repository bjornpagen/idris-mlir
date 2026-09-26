// RUN: idris-mlir-opt %s --idr-tail-loops | FileCheck %s
// rule: LOW-TAIL-1, LOW-TAIL-2, LOW-TAIL-4
module attributes {idr.version = 0 : i64, idr.entry = @r, idr.entry_kind = "int"} {
  // CHECK-LABEL: func.func private @sum(
  // CHECK: scf.while
  // CHECK: scf.if
  // CHECK: scf.condition
  // CHECK: idr.may_loop
  // CHECK-NEXT: scf.yield
  // CHECK-NOT: call @sum
  // CHECK-LABEL: func.func private @r(
  // CHECK: call @sum
  func.func private @sum(%n: i64 {idr.quantity = "w"}, %acc: i64 {idr.quantity = "w"}) -> i64 attributes {idr.name = "sum"} {
    %c0 = arith.constant 0 : i64
    %c1 = arith.constant 1 : i64
    %z = arith.cmpi eq, %n, %c0 : i64
    %r = scf.if %z -> i64 {
      scf.yield %acc : i64
    } else {
      %m = arith.subi %n, %c1 : i64
      %a = arith.addi %acc, %n : i64
      %t = func.call @sum(%m, %a) : (i64, i64) -> i64
      scf.yield %t : i64
    }
    return %r : i64
  }
  func.func private @r() -> i64 attributes {idr.name = "r"} {
    %c = arith.constant 10 : i64
    %z = arith.constant 0 : i64
    %s = func.call @sum(%c, %z) : (i64, i64) -> i64
    return %s : i64
  }
}
