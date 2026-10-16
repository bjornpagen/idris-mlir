// NEEDS-ACCEPTANCE: that total and not-total read the function's own `total` fact, each failing once on the function that holds the other.
// RUN: idris-mlir-opt %s --idr-expect=holds=total=@proved,not-total=@unproved -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=total=@unproved,not-total=@proved -o /dev/null 2> %t.err
// RUN: FileCheck %s < %t.err
// RUN: grep 'error: expected ' %t.err | count 2
// A function holds Idris's proof that its own loops end, or it does not:
// @proved does, @unproved does not.
// CHECK-DAG: error: expected total: @unproved does not hold Idris's proof of termination
// CHECK-DAG: error: expected not-total: @proved holds Idris's proof of termination
idr.program @proved root(@root) stage(first) {
  idr.func @proved(%x: i64) -> i64 attributes {total} {
    %r = arith.addi %x, %x : i64
    return %r : i64
  }
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
