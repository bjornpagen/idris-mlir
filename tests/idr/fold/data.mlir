// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s
// rule: IDR-TAG-1, IDR-FIELD-1, IDR-IF-1
module attributes {idr.version = 1 : i64, idr.entry = @r, idr.entry_kind = "int"} {
  idr.data @S attributes {idr.name = "S"} {
    idr.ctor @A tag 0 fields [] quantities [] {idr.name = "A"}
    idr.ctor @B tag 1 fields [i64] quantities ["w"] {idr.name = "B"}
  }
  // CHECK-LABEL: func.func @known(
  // CHECK-SAME: %[[X:.*]]: i64)
  // CHECK: %[[ONE:.*]] = arith.constant 1 : index
  // CHECK-NOT: idr.
  // CHECK: return %[[ONE]], %[[X]]
  func.func @known(%x: i64) -> (index, i64) {
    %s = idr.con @S::@B(%x) : (i64) -> !idr.data<@S>
    %t = idr.tag %s : !idr.data<@S>
    %f = idr.field %s[@B, 0] : !idr.data<@S> -> i64
    return %t, %f : index, i64
  }
  // CHECK-LABEL: func.func @switch(
  // CHECK-NOT: scf.index_switch
  // CHECK: arith.constant 7 : i64
  func.func @switch() -> i64 {
    %s = idr.con @S::@A() : () -> !idr.data<@S>
    %t = idr.tag %s : !idr.data<@S>
    %r = scf.index_switch %t -> i64
    case 0 {
      %a = arith.constant 7 : i64
      scf.yield %a : i64
    }
    default {
      %b = arith.constant 9 : i64
      scf.yield %b : i64
    }
    return %r : i64
  }
  func.func private @r() -> i64 attributes {idr.name = "r"} {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}
