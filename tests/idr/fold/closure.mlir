// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s
// A closure whose captures are constants is a constant.

func.func private @add(%a: i64, %b: i64) -> i64 {
  %r = arith.addi %a, %b : i64
  return %r : i64
}

// CHECK-LABEL: func.func @closures(
// CHECK-SAME: %[[X:.*]]: i64)
// CHECK-DAG: %[[C:.*]] = idr.constant #idr.closure<@add, [5]> : !idr.fn<(i64) -> (i64)>
// CHECK-DAG: %[[N:.*]] = idr.constant #idr.closure<@add, []> : !idr.fn<(i64, i64) -> (i64)>
// CHECK-DAG: %[[R:.*]] = idr.closure @add(%[[X]]) : (i64) -> !idr.fn<(i64) -> (i64)>
// CHECK: return %[[C]], %[[N]], %[[R]]
func.func @closures(%x: i64) -> (!idr.fn<(i64) -> (i64)>, !idr.fn<(i64, i64) -> (i64)>,
                                  !idr.fn<(i64) -> (i64)>) {
  %five = arith.constant 5 : i64
  %c = idr.closure @add(%five) : (i64) -> !idr.fn<(i64) -> (i64)>
  %n = idr.closure @add() : () -> !idr.fn<(i64, i64) -> (i64)>
  %r = idr.closure @add(%x) : (i64) -> !idr.fn<(i64) -> (i64)>
  return %c, %n, %r : !idr.fn<(i64) -> (i64)>, !idr.fn<(i64, i64) -> (i64)>,
                      !idr.fn<(i64) -> (i64)>
}
