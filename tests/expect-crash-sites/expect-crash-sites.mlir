// RUN: idris-mlir-opt %s --idr-expect=holds=crash-sites=@divides:1,crash-sites=@never:1,crash-sites=@safe:0,crash-sites=@two:2,crash-sites=@calls_never:0,crash-sites=@calls_divides:0 -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=crash-sites=@divides:0,crash-sites=@safe:1,crash-sites=@two:1,crash-sites=@two:3 -verify-diagnostics -o /dev/null
// A place that may crash is a guard, which crashes when its condition
// fails (@divides), or an op that never returns (@never); a function that
// only computes has none (@safe). The count is exact: two guards are two,
// neither one nor three (@two). Before lowering a call is no place of its
// own, whether its callee may crash (@calls_divides) or never returns
// (@calls_never): the places are the callee's, and only after lowering is
// a call of a function that never returns one.
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
  // expected-error @below {{expected crash-sites: @two may crash at 2 places, not 1}}
  // expected-error @below {{expected crash-sites: @two may crash at 2 places, not 3}}
  idr.func @two(%x: i64, %y: i64, %z: i64) -> i64 {
    %g = idr.check.nonzero %y, "division by zero" : i64
    %q = idr.divs %x, %g : i64
    %h = idr.check.nonzero %z, "division by zero" : i64
    %r = idr.divs %q, %h : i64
    return %r : i64
  }
  idr.func @calls_never(%x: i64) -> i64 {
    %r = idr.call @never(%x) : (i64) -> i64
    return %r : i64
  }
  idr.func @calls_divides(%x: i64, %y: i64) -> i64 {
    %r = idr.call @divides(%x, %y) : (i64, i64) -> i64
    return %r : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
