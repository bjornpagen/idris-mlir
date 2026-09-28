// RUN: idris-mlir-opt %s --idr-specialize | FileCheck %s
// RUN: idris-mlir-opt %s --idr-specialize --canonicalize --idr-specialize --canonicalize | FileCheck %s --check-prefix=NEXT
// rule: ELIM-SPEC-1
// A partially static list, [1, 2, n]: its spine and first two elements are
// the static shape, n is a runtime leaf and becomes the clone's parameter.
// Once the clone's match folds, the recursive call is on [2, n], which is
// specialized in turn.
module attributes {idr.program} {
  idr.data @L box {
    idr.ctor @Nil tag 0 () {quantities = []}
    idr.ctor @Cons tag 1 (i64, !idr.box<@L>) {quantities = ["w", "w"]}
  }
  func.func private @sum(%xs: !idr.box<@L> {idr.quantity = "w"}) -> i64 attributes {idr.total} {
    %r = idr.match %xs : !idr.box<@L> -> (i64) {
    case @Nil() {
      %z = arith.constant 0 : i64
      idr.yield %z : i64
    }
    case @Cons(%h: i64, %t: !idr.box<@L>) {
      %s = func.call @sum(%t) : (!idr.box<@L>) -> i64
      %a = arith.addi %h, %s : i64
      idr.yield %a : i64
    }
    }
    return %r : i64
  }
  // CHECK-LABEL: func.func private @use(
  // CHECK-SAME: %[[N:[a-z0-9_]+]]: i64
  // CHECK: call @sum$spec$1(%[[N]]) : (i64) -> i64
  func.func private @use(%n: i64 {idr.quantity = "w"}) -> i64 attributes {idr.total} {
    %c1 = arith.constant 1 : i64
    %c2 = arith.constant 2 : i64
    %nil = idr.con @L::@Nil() : () -> !idr.box<@L>
    %l3 = idr.con @L::@Cons(%n, %nil) : (i64, !idr.box<@L>) -> !idr.box<@L>
    %l2 = idr.con @L::@Cons(%c2, %l3) : (i64, !idr.box<@L>) -> !idr.box<@L>
    %l1 = idr.con @L::@Cons(%c1, %l2) : (i64, !idr.box<@L>) -> !idr.box<@L>
    %r = func.call @sum(%l1) : (!idr.box<@L>) -> i64
    return %r : i64
  }
  func.func @Main.main() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
  // CHECK-LABEL: func.func private @sum$spec$1(
  // CHECK-SAME: %[[M:[a-z0-9_]+]]: i64 {idr.quantity = "w"}) -> i64
  // CHECK-DAG: idr.con @L::@Nil()
  // CHECK-DAG: idr.con @L::@Cons(%[[M]],
  // CHECK: idr.match

  // NEXT-LABEL: func.func private @sum$spec$1(
  // NEXT-SAME: %[[M:[a-z0-9_]+]]: i64
  // NEXT: %[[S:.*]] = call @sum$spec$2(%[[M]]) : (i64) -> i64
  // NEXT-LABEL: func.func private @sum$spec$2(
  // NEXT-SAME: attributes {idr.origin = "sum", idr.total}
}
