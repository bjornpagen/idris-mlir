// RUN: idris-mlir-opt %s --idr-expect=holds=computes-nothing=@guards,computes-nothing=@never,computes-nothing=@given -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=computes-nothing=@computes -verify-diagnostics -o /dev/null
// A function that computes nothing keeps only what may crash and what ends
// its blocks: a guard (@guards), a crash (@never), or nothing but the
// return of what it was given (@given). An op that computes a value is
// something else left (@computes).
idr.program @"computes-nothing" root(@root) stage(first) {
  idr.func @guards(%x: i64, %y: i64) -> i64 {
    %g = idr.check.nonzero %y, "division by zero" : i64
    return %x : i64
  }
  idr.func @never(%x: i64) -> i64 {
    idr.crash "unhandled input for never"
    ub.unreachable
  }
  idr.func @given(%x: i64) -> i64 {
    return %x : i64
  }
  idr.func @computes(%x: i64) -> i64 {
    // expected-error @below {{expected computes-nothing: }}
    %y = arith.addi %x, %x : i64
    return %y : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
