// RUN: idris-mlir-opt %s --idr-isolate > %t.mlir
// RUN: FileCheck %s --check-prefix=OUTER --implicit-check-not=idr.lambda < %t.mlir
// RUN: FileCheck %s --check-prefix=BODY < %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-isolate > %t.again.mlir
// RUN: diff %t.mlir %t.again.mlir
// RUN: idris-mlir-opt %s --idr-isolate --mlir-print-debuginfo --mlir-print-local-scope | FileCheck %s --check-prefix=LOC
// idr-isolate gives the body of each idr.lambda a private function of its
// own, `<f>$lam<n>`, and makes the lambda an idr.closure of it over the
// values the body uses from above, in the order the body first uses them:
// here a field a match bound, then a parameter of the enclosing function.
// The function takes those captures first, then the lambda's parameters,
// and returns what the body yielded. Its code is the enclosing function's:
// it breaks last when that one does, it is total, and its location names
// the enclosing definition, so idr-expect finds it there. A body that uses
// nothing from above is a closure of no captures. Nothing is left to
// isolate after the pass, so a second run changes nothing.
// OUTER-LABEL: func.func private @Main.adder(
// OUTER-SAME: %[[M:[^:]*]]: !idr.data<@Maybe>, %[[K:[^:]*]]: i64)
// OUTER: case @Just(%[[J:[^:]*]]: i64) {
// OUTER-NEXT: %[[C:.*]] = idr.closure @Main.adder$lam{{[0-9]+}}(%[[J]], %[[K]]) : (i64, i64) -> !idr.fn<(i64) -> i64>
// OUTER-NEXT: idr.yield %[[C]] : !idr.fn<(i64) -> i64>
// OUTER: default {
// OUTER-NEXT: %[[D:.*]] = idr.closure @Main.adder$lam{{[0-9]+}}() : () -> !idr.fn<(i64) -> i64>
// OUTER-NEXT: idr.yield %[[D]] : !idr.fn<(i64) -> i64>
// BODY: func.func private @Main.adder$lam{{[0-9]+}}(%[[J:[^:]*]]: i64, %[[K:[^:]*]]: i64, %[[X:[^:]*]]: i64) -> i64
// BODY-SAME: attributes {idr.break_last, idr.total}
// BODY-NEXT: %[[A:.*]] = arith.addi %[[J]], %[[K]] : i64
// BODY-NEXT: %[[B:.*]] = arith.addi %[[A]], %[[X]] : i64
// BODY-NEXT: return %[[B]] : i64
// LOC: loc("Main.adder"("Main.idr":4:12))
module {
  idr.data @Maybe {
    idr.ctor @Nothing ()
    idr.ctor @Just (i64)
  }
  func.func private @Main.adder(%m: !idr.data<@Maybe>, %k: i64) -> !idr.fn<(i64) -> (i64)> attributes {idr.break_last} {
    %f = idr.match %m : !idr.data<@Maybe> -> (!idr.fn<(i64) -> (i64)>) {
    case @Just(%j: i64) {
      %l = idr.lambda : !idr.fn<(i64) -> (i64)> {
      ^bb0(%x: i64):
        %a = arith.addi %j, %k : i64
        %b = arith.addi %a, %x : i64
        idr.yield %b : i64
      } loc("Main.idr":4:12)
      idr.yield %l : !idr.fn<(i64) -> (i64)>
    }
    default {
      %l = idr.lambda : !idr.fn<(i64) -> (i64)> {
      ^bb0(%x: i64):
        idr.yield %x : i64
      } loc("Main.idr":5:12)
      idr.yield %l : !idr.fn<(i64) -> (i64)>
    }
    }
    return %f : !idr.fn<(i64) -> (i64)>
  } loc("Main.adder"("Main.idr":3:1))
  func.func @Main.main(%w: !idr.world) -> !idr.world {
    %n = idr.con @Maybe::@Nothing() : () -> !idr.data<@Maybe>
    %k = arith.constant 1 : i64
    %f = func.call @Main.adder(%n, %k) : (!idr.data<@Maybe>, i64) -> !idr.fn<(i64) -> (i64)>
    %r = idr.apply %f(%k) : !idr.fn<(i64) -> (i64)>
    %w1 = idr.io.put_int signed %r, %w : i64
    return %w1 : !idr.world
  }
}
