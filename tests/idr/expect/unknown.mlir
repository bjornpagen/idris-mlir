// NEEDS-ACCEPTANCE: that each unknown name is refused once, at the module (line 0, the implicit module's location, written @-n from each annotation's own line), and the run passes under -verify-diagnostics.
// RUN: idris-mlir-opt %s --idr-expect=holds=breaks-last,every-cycle-has-breaker,in-bounds=@f,bounds-checked=@f,pure-array-loops -verify-diagnostics -o /dev/null
// A property idr-expect does not know is an error, so a misspelled name,
// or a property of a mechanism that is gone, cannot pass where it stands;
// each is refused, and the next request is still read.
// expected-error @-6 {{idr-expect: no property named breaks-last}}
// expected-error @-7 {{idr-expect: no property named every-cycle-has-breaker}}
// expected-error @-8 {{idr-expect: no property named in-bounds}}
// expected-error @-9 {{idr-expect: no property named bounds-checked}}
// expected-error @-10 {{idr-expect: no property named pure-array-loops}}
idr.program @unknown root(@root) stage(first) {
  idr.func @f(%x: i64) -> i64 {
    return %x : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
