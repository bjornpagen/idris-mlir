// RUN: idris-mlir-opt %s --mlir-disable-threading --canonicalize --idr-expect=holds=folds-balanced > %t.mlir
// RUN: FileCheck %s < %t.mlir
// The folders own what the runtime returns and release each reference once,
// also when an operation returns one of its arguments with one more
// reference: appending the empty string, reversing an empty one. The
// runtime they call holds no live cell afterwards.
// CHECK-LABEL: func.func @folds(
// CHECK-DAG: idr.constant "abc" : !idr.str
// CHECK-DAG: idr.constant "" : !idr.str
// CHECK-DAG: idr.constant #idr.big<"-123456789012345678901234567890"> : !idr.big
// CHECK-NOT: idr.str.
// CHECK-NOT: idr.big.
func.func @folds() -> (!idr.str, !idr.str, !idr.str, !idr.big) {
  %e = idr.constant "" : !idr.str
  %x = idr.constant "abc" : !idr.str
  %a = idr.str.append %e, %x
  %b = idr.str.append %x, %e
  %r = idr.str.reverse %e
  %big = idr.constant #idr.big<"123456789012345678901234567890"> : !idr.big
  %n = idr.big.neg %big
  return %a, %b, %r, %n : !idr.str, !idr.str, !idr.str, !idr.big
}
