// RUN: idris-mlir-opt %s --idr-expect=holds=largest-function=100 -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=largest-function=4 -o /dev/null 2> %t.small.err
// RUN: FileCheck %s --check-prefix=SMALL < %t.small.err
// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=largest-function=many -o /dev/null 2> %t.bad.err
// RUN: FileCheck %s --check-prefix=BAD < %t.bad.err
// A bound on the size of every function, counted as the inline decisions
// count it, which is how a test states that inlining stopped at the cap.
// Each function past the bound is one error, with its size; a bound that
// is no number is an error of its own.
// SMALL: error: expected largest-function: @big holds {{[0-9]+}} operations, more than 4
// SMALL-NOT: @small
// BAD: error: expected largest-function: name the bound, as largest-function=<n>
idr.program @"largest-function" root(@main) stage(first) {
  idr.func @small(%x: i64) -> i64 {
    return %x : i64
  }
  idr.func @big(%x: i64) -> i64 {
    %a = arith.addi %x, %x : i64
    %b = arith.muli %a, %a : i64
    %c = arith.subi %b, %x : i64
    %d = arith.addi %c, %a : i64
    %e = arith.muli %d, %b : i64
    %f = arith.addi %e, %c : i64
    return %f : i64
  }
  idr.func @main() -> i64 {
    %c = arith.constant 2 : i64
    %s = idr.call @small(%c) : (i64) -> i64
    %b = idr.call @big(%s) : (i64) -> i64
    return %b : i64
  }
}
