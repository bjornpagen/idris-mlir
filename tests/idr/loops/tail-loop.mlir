// RUN: idris-mlir-opt %s --idr-tail-loops > %t.mlir
// RUN: FileCheck %s < %t.mlir
// RUN: idris-mlir-opt %t.mlir --inline --canonicalize | FileCheck %s --check-prefix=KEPT
// rule: LOW-TAIL-4, LOW-TAIL-5, SEM-EVAL-5, OPT-SAFE-1
// A self tail call in a region of a match whose results are returned
// becomes one scf.while: the before region is the body, and each tail
// position yields (continue, arguments, results). A total function's loop
// gets no idr.may_loop; a partial one's does, and keeps the loop alive even
// when nothing uses its result. A call that is not in tail position stays.

// CHECK-LABEL: func.func private @count(
// CHECK-SAME: %[[ACC:[a-z0-9_]+]]: i64 {idr.quantity = "w"}, %[[N:[a-z0-9_]+]]: i64 {idr.quantity = "w"}) -> i64
// CHECK-NEXT: %[[L:.*]]:3 = scf.while (%[[A:.*]] = %[[ACC]], %[[M:.*]] = %[[N]]) : (i64, i64) -> (i64, i64, i64) {
// CHECK-NOT: idr.may_loop
// CHECK: %[[P:.*]]:4 = idr.match_lit %[[M]] : i64 -> (i1, i64, i64, i64) {
// CHECK-NEXT: case 0 {
// CHECK-NEXT: %[[F:.*]] = arith.constant false
// CHECK-NEXT: %[[U1:.*]] = ub.poison : i64
// CHECK-NEXT: %[[U2:.*]] = ub.poison : i64
// CHECK-NEXT: idr.yield %[[F]], %[[U1]], %[[U2]], %[[A]] : i1, i64, i64, i64
// CHECK: default {
// CHECK: %[[T:.*]] = arith.constant true
// CHECK-NEXT: %[[U3:.*]] = ub.poison : i64
// CHECK-NEXT: idr.yield %[[T]], %{{.*}}, %{{.*}}, %[[U3]] : i1, i64, i64, i64
// CHECK: scf.condition(%[[P]]#0) %[[P]]#1, %[[P]]#2, %[[P]]#3 : i64, i64, i64
// CHECK-NEXT: } do {
// CHECK-NEXT: ^bb0(%[[X:.*]]: i64, %[[Y:.*]]: i64, %{{.*}}: i64):
// CHECK-NEXT: scf.yield %[[X]], %[[Y]] : i64, i64
// CHECK: return %[[L]]#2 : i64
// CHECK-NOT: call @count

// CHECK-LABEL: func.func private @spin(
// CHECK: scf.while
// CHECK-NEXT: idr.may_loop
// CHECK: scf.condition(%true)

// CHECK-LABEL: func.func private @fib(
// CHECK-NOT: scf.while
// CHECK: call @fib
// CHECK: call @fib

// Once the loops are inlined into @Main.main, where their results are
// unused, the total one is dead code and goes; the partial one stays.
// KEPT-LABEL: func.func @Main.main(
// KEPT: scf.while
// KEPT-NEXT: idr.may_loop
// KEPT-NOT: scf.while
// KEPT: call @fib
module attributes {idr.program} {
  func.func private @count(%acc: i64 {idr.quantity = "w"}, %n: i64 {idr.quantity = "w"}) -> i64 attributes {idr.total} {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %acc : i64
    }
    default {
      %c1 = arith.constant 1 : i64
      %a = arith.addi %acc, %c1 : i64
      %m = arith.subi %n, %c1 : i64
      %x = func.call @count(%a, %m) : (i64, i64) -> i64
      idr.yield %x : i64
    }
    }
    return %r : i64
  }
  // spin x = spin (x + 1)
  func.func private @spin(%x: i64 {idr.quantity = "w"}) -> i64 {
    %c1 = arith.constant 1 : i64
    %y = arith.addi %x, %c1 : i64
    %r = func.call @spin(%y) : (i64) -> i64
    return %r : i64
  }
  func.func private @fib(%n: i64 {idr.quantity = "w"}) -> i64 {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %n : i64
    }
    case 1 {
      idr.yield %n : i64
    }
    default {
      %c1 = arith.constant 1 : i64
      %c2 = arith.constant 2 : i64
      %a = arith.subi %n, %c1 : i64
      %b = arith.subi %n, %c2 : i64
      %x = func.call @fib(%a) : (i64) -> i64
      %y = func.call @fib(%b) : (i64) -> i64
      %s = arith.addi %x, %y : i64
      idr.yield %s : i64
    }
    }
    return %r : i64
  }
  func.func @Main.main() -> i64 {
    %c0 = arith.constant 0 : i64
    %c9 = arith.constant 9 : i64
    %a = func.call @count(%c0, %c9) : (i64, i64) -> i64
    %b = func.call @spin(%c0) : (i64) -> i64
    %c = func.call @fib(%c9) : (i64) -> i64
    return %c : i64
  }
}
