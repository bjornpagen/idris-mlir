// RUN: idris-mlir-opt %s --idr-expect=holds=largest-function=100,largest-function=7 -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=largest-function=6,largest-function=many -verify-diagnostics -o /dev/null
// expected-error @-3 {{idr-expect: largest-function=many does not read as largest-function=<n>}}
// A bound on the size of every function, counted as the inline decisions
// count it, which is how a test states that inlining stopped at the cap.
// Each function past the bound is one error, with its size; a bound that
// is no number is refused at the request, before the property runs. The
// bound is inclusive: @big, of seven operations (six that compute and its
// return), is within 7 and past 6, and @main and @small are within both.
idr.program @"largest-function" root(@main) stage(first) types #idr.types<> {
  idr.func @small(%x: i64) -> i64 {
    return %x : i64
  }
  // expected-error-re @below {{expected largest-function: @big holds {{[0-9]+}} operations, more than 6}}
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
