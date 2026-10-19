// RUN: idris-mlir-opt %s --idr-expect=holds=breaks-last,every-cycle-has-breaker,in-bounds=@f,bounds-checked=@f,pure-array-loops,no-closure,Stage=first,calls-closed-=@f:@f -verify-diagnostics -o /dev/null
// A property idr-expect does not know is an error, so a misspelled name,
// or a property of a mechanism that is gone, cannot pass where it stands;
// each is refused, and the next request is still read. A name is read
// exactly: one letter short of a known one (no-closure), another case
// (Stage), one character more (calls-closed-) are no property.
// expected-error @-7 {{idr-expect: no property named breaks-last}}
// expected-error @-8 {{idr-expect: no property named every-cycle-has-breaker}}
// expected-error @-9 {{idr-expect: no property named in-bounds}}
// expected-error @-10 {{idr-expect: no property named bounds-checked}}
// expected-error @-11 {{idr-expect: no property named pure-array-loops}}
// expected-error @-12 {{idr-expect: no property named no-closure}}
// expected-error @-13 {{idr-expect: no property named Stage}}
// expected-error @-14 {{idr-expect: no property named calls-closed-}}
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
