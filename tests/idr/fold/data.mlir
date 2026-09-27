// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s
// rule: IDR-TAG-1, IDR-FIELD-1, IDR-IF-1
module attributes {idr.version = 1 : i64, idr.entry = @r, idr.entry_kind = "int"} {
  idr.data @S attributes {idr.name = "S"} {
    idr.ctor @A tag 0 fields [] quantities [] {idr.name = "A"}
    idr.ctor @B tag 1 fields [i64] quantities ["w"] {idr.name = "B"}
  }
  // CHECK-LABEL: func.func @known(
  // CHECK-SAME: %[[X:.*]]: i64)
  // CHECK: %[[ONE:.*]] = arith.constant 1 : i64
  // CHECK-NOT: idr.
  // CHECK: return %[[ONE]], %[[X]]
  func.func @known(%x: i64) -> (i64, i64) {
    %s = idr.con @S::@B(%x) : (i64) -> !idr.data<@S>
    %t = idr.tag %s : !idr.data<@S>
    %f = idr.field %s[@B, 0] : !idr.data<@S> -> i64
    return %t, %f : i64, i64
  }
  // CHECK-LABEL: func.func @switch(
  // CHECK-NOT: cf.switch
  // CHECK: arith.constant 7 : i64
  func.func @switch() -> i64 {
    %s = idr.con @S::@A() : () -> !idr.data<@S>
    %t = idr.tag %s : !idr.data<@S>
    cf.switch %t : i64, [default: ^other, 0: ^a]
  ^a:
    %a = arith.constant 7 : i64
    return %a : i64
  ^other:
    %b = arith.constant 9 : i64
    return %b : i64
  }
  func.func private @r() -> i64 attributes {idr.name = "r"} {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}
