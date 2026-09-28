// RUN: idris-mlir-opt %s --idr-specialize > %t.mlir
// RUN: FileCheck %s < %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-specialize > %t2.mlir
// RUN: diff %t.mlir %t2.mlir
// rule: ELIM-SPEC-1, FE-DET-1
// A closure passed to a recursive map. Its label is static and its capture
// a runtime leaf: the clone of @map rebuilds the closure over a new
// parameter, and the recursive call, which passes the same closure, calls
// the clone itself. Nothing is left to specialize after that.
// CHECK: idr.clone_counts = {map = 1 : i64}
module attributes {idr.program} {
  idr.data @L box {
    idr.ctor @Nil tag 0 () {quantities = []}
    idr.ctor @Cons tag 1 (i64, !idr.box<@L>) {quantities = ["w", "w"]}
  }
  func.func private @add(%a: i64 {idr.quantity = "w"}, %x: i64 {idr.quantity = "w"}) -> i64 attributes {idr.total} {
    %y = arith.addi %a, %x : i64
    return %y : i64
  }
  // CHECK-LABEL: func.func private @map(
  // CHECK: call @map(
  func.func private @map(%f: !idr.fn<(i64) -> (i64)> {idr.quantity = "w"}, %xs: !idr.box<@L> {idr.quantity = "w"}) -> !idr.box<@L> attributes {idr.total} {
    %r = idr.match %xs : !idr.box<@L> -> (!idr.box<@L>) {
    case @Nil() {
      %n = idr.con @L::@Nil() : () -> !idr.box<@L>
      idr.yield %n : !idr.box<@L>
    }
    case @Cons(%h: i64, %t: !idr.box<@L>) {
      %h2 = idr.apply %f(%h) : !idr.fn<(i64) -> (i64)>
      %t2 = func.call @map(%f, %t) : (!idr.fn<(i64) -> (i64)>, !idr.box<@L>) -> !idr.box<@L>
      %c = idr.con @L::@Cons(%h2, %t2) : (i64, !idr.box<@L>) -> !idr.box<@L>
      idr.yield %c : !idr.box<@L>
    }
    }
    return %r : !idr.box<@L>
  }
  // CHECK-LABEL: func.func private @use(
  // CHECK-SAME: %[[N:.*]]: i64 {idr.quantity = "w"}, %[[XS:.*]]: !idr.box<@L> {idr.quantity = "w"})
  // CHECK: %[[R:.*]] = call @[[M:map\$spec\$[0-9]+]](%[[N]], %[[XS]])
  // CHECK-NEXT: return %[[R]]
  func.func private @use(%n: i64 {idr.quantity = "w"}, %xs: !idr.box<@L> {idr.quantity = "w"}) -> !idr.box<@L> attributes {idr.total} {
    %f = idr.closure @add(%n) : (i64) -> !idr.fn<(i64) -> (i64)>
    %r = func.call @map(%f, %xs) : (!idr.fn<(i64) -> (i64)>, !idr.box<@L>) -> !idr.box<@L>
    return %r : !idr.box<@L>
  }
  func.func @Main.main() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
  // CHECK: func.func private @[[M]](
  // CHECK-SAME: %[[A:.*]]: i64 {idr.hole = 0 : i64, idr.quantity = "w"}, %[[L:.*]]: !idr.box<@L> {idr.hole = 1 : i64, idr.quantity = "w"})
  // CHECK-SAME: idr.origin = "map"
  // CHECK-SAME: idr.spec_key = "{{.*}}closure{{.*}}@add{{.*}}"
  // CHECK-SAME: idr.total
  // CHECK: case @Cons(%[[H:.*]]: i64, %[[T:.*]]: !idr.box<@L>)
  // CHECK-NEXT: func.call @add(%[[A]], %[[H]])
  // CHECK-NEXT: call @[[M]](%[[A]], %[[T]])
}
