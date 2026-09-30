// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s
// The runtime folds the predecessor of a constant; zero has none, so its
// predecessor, on a path a match excludes, stays as it is.
// CHECK-LABEL: func.func @preds(
// CHECK-DAG: %[[FOUR:.*]] = idr.constant #idr.big<"4"> : !idr.nat
// CHECK-DAG: %[[ZERO:.*]] = idr.constant #idr.big<"0"> : !idr.nat
// CHECK-DAG: %[[BIG:.*]] = idr.constant #idr.big<"18446744073709551616"> : !idr.nat
// CHECK: %[[NONE:.*]] = idr.big.pred %[[ZERO]]
// CHECK: return %[[FOUR]], %[[NONE]], %[[BIG]]
func.func @preds() -> (!idr.nat, !idr.nat, !idr.nat) {
  %five = idr.constant #idr.big<"5"> : !idr.nat
  %zero = idr.constant #idr.big<"0"> : !idr.nat
  %large = idr.constant #idr.big<"18446744073709551617"> : !idr.nat
  %a = idr.big.pred %five
  %b = idr.big.pred %zero
  %c = idr.big.pred %large
  return %a, %b, %c : !idr.nat, !idr.nat, !idr.nat
}
