// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=folds-balanced > %t.mlir
// RUN: FileCheck %s < %t.mlir
// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(func.func(canonicalize),idr-expect{holds=folds-balanced})' -o /dev/null
// The folders own what the runtime returns and release each reference once,
// also when an operation returns one of its arguments with one more
// reference: appending the empty string, reversing an empty one. No fold
// leaves a cell live. The count is per fold, whatever thread folds: the
// last run folds the two functions on the pool's threads and checks on the
// main one, which shows that folding elsewhere does not fail the check. No
// folder leaks, so no fixture shows a leak on another thread being seen.
// CHECK-LABEL: func.func @folds(
// CHECK-DAG: idr.constant "abc" : !idr.str
// CHECK-DAG: idr.constant "" : !idr.str
// CHECK-DAG: idr.constant #idr.big<"-123456789012345678901234567890"> : !idr.big
// CHECK-NOT: idr.str.
// CHECK-NOT: idr.big.
// CHECK-LABEL: func.func @more(
// CHECK-DAG: idr.constant "cba" : !idr.str
// CHECK-DAG: idr.constant #idr.big<"98765432109876543210"> : !idr.big
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

func.func @more() -> (!idr.str, !idr.big) {
  %x = idr.constant "abc" : !idr.str
  %r = idr.str.reverse %x
  %big = idr.constant #idr.big<"-98765432109876543210"> : !idr.big
  %n = idr.big.neg %big
  return %r, %n : !idr.str, !idr.big
}
