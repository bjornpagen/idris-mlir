// RUN: idris-mlir-opt %s --idr-expect=holds=no-guards=@proved -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=no-guards=@kept -verify-diagnostics -o /dev/null
// A function keeps no guard when every condition its partial primitives
// need is proven where it runs: a division by a nonzero constant needs
// none (@proved). Each guard left is one error (@kept).
idr.program @guards root(@root) stage(first) {
  idr.func @proved(%x: i64) -> i64 {
    %two = arith.constant 2 : i64
    %r = idr.divs %x, %two : i64
    return %r : i64
  }
  idr.func @kept(%x: i64, %y: i64) -> i64 {
    // expected-error @below {{expected no-guards: }}
    %g = idr.check.nonzero %y, "division by zero" : i64
    %r = idr.divs %x, %g : i64
    return %r : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
