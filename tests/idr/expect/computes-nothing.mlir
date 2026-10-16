// NEEDS-ACCEPTANCE: that computes-nothing holds of a function of a guard and of one of a crash, and fails once at the one op of @computes that computes a value.
// RUN: idris-mlir-opt %s --idr-expect=holds=computes-nothing=@guards,computes-nothing=@never -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=computes-nothing=@computes -o /dev/null 2> %t.err
// RUN: FileCheck %s < %t.err
// RUN: grep 'error: expected ' %t.err | count 1
// A function that computes nothing keeps only what may crash and what ends
// its blocks: a guard (@guards), a crash (@never). An op that computes a
// value is something else left (@computes).
// CHECK-DAG: error: expected computes-nothing: {{.*}} is left in @computes
idr.program @"computes-nothing" root(@root) stage(first) {
  idr.func @guards(%x: i64, %y: i64) -> i64 {
    %g = idr.check.nonzero %y, "division by zero" : i64
    return %x : i64
  }
  idr.func @never(%x: i64) -> i64 {
    idr.crash "unhandled input for never"
    ub.unreachable
  }
  idr.func @computes(%x: i64) -> i64 {
    %y = arith.addi %x, %x : i64
    return %y : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
