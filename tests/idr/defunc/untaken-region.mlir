// RUN: idris-mlir-opt %s --idr-defunctionalize > %t.mlir
// RUN: FileCheck %s --implicit-check-not='{{(idr\.| )closure }}' --implicit-check-not=ub.poison < %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=no-closures -o /dev/null
// NEEDS-ACCEPTANCE: the dispatch's printed form, as C06's conversion writes it.
// The solve follows every edge the ops declare, whether or not the path
// runs: here the one call of @g is in the region a match on a constant
// never takes, and the closure it passes still reaches @g's parameter.
// So @g's apply is a dispatch over @add, the call passes the closure's
// constructor, and nothing is poison; which regions run is the
// optimizer's to find afterwards, as a case of a known literal.
// CHECK-LABEL: idr.func @g(
// CHECK: case @add(
// CHECK: call @add(
// CHECK-LABEL: idr.func @Prog.main(
// CHECK: con {{.*}}@add(
// CHECK: call @g(
idr.program @"untaken-region" root(@Prog.main) stage(higher) {
  idr.func @add(%k: i64, %x: i64) -> i64 attributes {total} {
    %r = arith.addi %k, %x : i64
    return %r : i64
  }
  idr.func @g(%f: !idr.fn<(i64) -> (i64)>) -> i64 {
    %one = arith.constant 1 : i64
    %r = idr.apply %f(%one) : !idr.fn<(i64) -> (i64)>
    return %r : i64
  }
  idr.func @Prog.main() -> i64 {
    %k = arith.constant 2 : i64
    %c = idr.closure @add(%k) : (i64) -> !idr.fn<(i64) -> (i64)>
    %zero = arith.constant 0 : i64
    %r = idr.match_lit %zero : i64 -> (i64) {
    case 0 {
      idr.yield %zero : i64
    }
    default {
      %v = idr.call @g(%c) : (!idr.fn<(i64) -> (i64)>) -> i64
      idr.yield %v : i64
    }
    }
    return %r : i64
  }
}
