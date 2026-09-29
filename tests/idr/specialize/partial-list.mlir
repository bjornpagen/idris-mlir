// RUN: idris-mlir-opt %s --idr-specialize --canonicalize | FileCheck %s
// A partially static list, [1, 2, n]: its spine and first two elements are
// the static shape, n is a runtime leaf and becomes the clone's parameter.
// The clone is folded when it is made, so its match folds and the recursive
// call is on [2, n], which is specialized in the same run, and so on down to
// [n]; the call on [] is closed and left to idr-eval. The list is @sum's
// decreasing parameter, and small, so it unrolls: no list is built at
// runtime.
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
  // CHECK-NOT: idr.con
  // CHECK: call @[[S1:sum\$spec\$[0-9]+]](%[[N]]) : (i64) -> i64
  // CHECK-NEXT: return
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
  // CHECK: func.func private @[[S1]](
  // CHECK-SAME: %[[M:[a-z0-9_]+]]: i64 {{.*}}) -> i64
  // CHECK: call @[[S2:sum\$spec\$[0-9]+]](%[[M]]) {{.*}}: (i64) -> i64
  // CHECK: func.func private @[[S2]](
  // CHECK: call @[[S3:sum\$spec\$[0-9]+]](%[[M2:[^)]*]]) {{.*}}: (i64) -> i64
  // CHECK: func.func private @[[S3]](
  // CHECK: call @sum(%{{[^)]*}}) {{.*}}: (!idr.box<@L>) -> i64
}
