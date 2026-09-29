// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s
// The runtime folds the predecessor of a constant; zero has none, so its
// predecessor, on a path a match excludes, stays as it is.
// CHECK-LABEL: func.func @preds(
// CHECK-DAG: %[[FOUR:.*]] = idr.constant #idr.big<"4"> : !idr.big
// CHECK-DAG: %[[ZERO:.*]] = idr.constant #idr.big<"0"> : !idr.big
// CHECK-DAG: %[[BIG:.*]] = idr.constant #idr.big<"18446744073709551616"> : !idr.big
// CHECK: %[[NONE:.*]] = idr.big.pred %[[ZERO]]
// CHECK: return %[[FOUR]], %[[NONE]], %[[BIG]]
func.func @preds() -> (!idr.big, !idr.big, !idr.big) {
  %five = idr.constant #idr.big<"5"> : !idr.big
  %zero = idr.constant #idr.big<"0"> : !idr.big
  %large = idr.constant #idr.big<"18446744073709551617"> : !idr.big
  %a = idr.big.pred %five
  %b = idr.big.pred %zero
  %c = idr.big.pred %large
  return %a, %b, %c : !idr.big, !idr.big, !idr.big
}
