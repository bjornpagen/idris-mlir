// RUN: idris-mlir-opt %s --idr-expect=holds=crash-sites=@divides:1,crash-sites=@never:1,crash-sites=@safe:0 -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=crash-sites=@divides:0,crash-sites=@safe:1 -verify-diagnostics -o /dev/null
// A place that may crash is a guard, which crashes when its condition
// fails (@divides), or an op that never returns (@never); a function that
// only computes has none (@safe).
idr.program @"crash-sites" root(@root) stage(first) {
  // expected-error @below {{expected crash-sites: }}
  idr.func @divides(%x: i64, %y: i64) -> i64 {
    %g = idr.check.nonzero %y, "division by zero" : i64
    %q = idr.divs %x, %g : i64
    return %q : i64
  }
  idr.func @never(%x: i64) -> i64 {
    idr.crash "unhandled input for never"
    ub.unreachable
  }
  // expected-error @below {{expected crash-sites: }}
  idr.func @safe(%x: i64) -> i64 {
    %y = arith.addi %x, %x : i64
    return %y : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
