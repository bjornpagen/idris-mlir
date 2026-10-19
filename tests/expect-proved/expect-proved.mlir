// RUN: idris-mlir-opt %s --idr-expect=holds=total=@proved,not-total=@unproved -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=total=@unproved,not-total=@proved -verify-diagnostics -o /dev/null
// A function holds Idris's proof that its own loops end, or it does not:
// @proved does, @unproved does not.
idr.program @proved root(@root) stage(first) {
  // expected-error @below {{expected not-total: }}
  idr.func @proved(%x: i64) -> i64 attributes {total} {
    %r = arith.addi %x, %x : i64
    return %r : i64
  }
  // expected-error @below {{expected total: }}
  idr.func @unproved(%x: i64) -> i64 {
    %r = arith.muli %x, %x : i64
    return %r : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
