// RUN: idris-mlir-opt %s --idr-defunctionalize > %t.mlir
// RUN: FileCheck %s < %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-check-profile
// rule: ELIM-CLOS-1, SEM-LAZY-1, PROF-HEAP-2
// A Lazy value picked at runtime, stored in a field and forced later: the
// suspensions become constructors of a sum, the field's type follows, and
// forcing is a match that calls the suspended function.
// CHECK: idr.data @fn$0 {
// CHECK-NEXT: idr.ctor @later tag 0 (i64) {quantities = ["w"]}
// CHECK-NEXT: idr.ctor @now tag 1 () {quantities = []}
// CHECK: idr.data @Box {
// CHECK-NEXT: idr.ctor @MkBox tag 0 (!idr.data<@fn$0>) {quantities = ["w"]}
// CHECK-NOT: !idr.fn
// CHECK-LABEL: func.func @Main.main(
// CHECK: %[[L:.*]] = idr.field %{{.*}}[@MkBox, 0] : !idr.data<@Box> -> !idr.data<@fn$0>
// CHECK-NEXT: idr.match %[[L]] : !idr.data<@fn$0> -> (i64) {
// CHECK-NEXT: case @later(%[[X:.*]]: i64) {
// CHECK-NEXT: call @later(%[[X]]) : (i64) -> i64
// CHECK: case @now() {
// CHECK-NEXT: call @now() : () -> i64
module attributes {idr.program} {
  idr.data @Box {
    idr.ctor @MkBox tag 0 (!idr.fn<() -> (i64)>) {quantities = ["w"]}
  }
  func.func private @now() -> i64 attributes {idr.total} {
    %c = arith.constant 7 : i64
    return %c : i64
  }
  func.func private @later(%x: i64 {idr.quantity = "w"}) -> i64 attributes {idr.total} {
    %y = arith.muli %x, %x : i64
    return %y : i64
  }
  func.func @Main.main(%w: !idr.world {idr.quantity = "1"}) -> !idr.world {
    %c, %w1 = idr.io.get_char %w
    %n = arith.extui %c : i32 to i64
    %s = idr.match_lit %n : i64 -> (!idr.fn<() -> (i64)>) {
    case 65 {
      %a = idr.closure @now() : () -> !idr.fn<() -> (i64)>
      idr.yield %a : !idr.fn<() -> (i64)>
    }
    default {
      %b = idr.closure @later(%n) : (i64) -> !idr.fn<() -> (i64)>
      idr.yield %b : !idr.fn<() -> (i64)>
    }
    }
    %box = idr.con @Box::@MkBox(%s) : (!idr.fn<() -> (i64)>) -> !idr.data<@Box>
    %l = idr.field %box[@MkBox, 0] : !idr.data<@Box> -> !idr.fn<() -> (i64)>
    %r = idr.apply %l() : !idr.fn<() -> (i64)>
    %w2 = idr.io.put_int signed %r, %w1 : i64
    return %w2 : !idr.world
  }
}
