// NEEDS-ACCEPTANCE: that counted-loop holds of an scf.for and fails once at the scf.while of @tested and once of @straight, which has no loop.
// RUN: idris-mlir-opt %s --idr-expect=holds=counted-loop=@counted -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=counted-loop=@tested,counted-loop=@straight -o /dev/null 2> %t.err
// RUN: FileCheck %s < %t.err
// RUN: grep 'error: expected ' %t.err | count 2
// A loop that counts to a bound with a step says its trip count (@counted,
// an scf.for); one that runs until its own test fails does not (@tested,
// an scf.while); and a function with no loop has none to count.
// CHECK-DAG: error: expected counted-loop: a loop of @tested has no trip count
// CHECK-DAG: error: expected counted-loop: @straight has no loop
idr.program @"counted-loop" root(@root) stage(first) {
  idr.func @counted(%n: index, %acc: i64) -> i64 {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %r = scf.for %i = %c0 to %n step %c1 iter_args(%a = %acc) -> (i64) {
      %x = arith.index_cast %i : index to i64
      %b = arith.addi %a, %x : i64
      scf.yield %b : i64
    }
    return %r : i64
  }
  idr.func @tested(%n: i64) -> i64 {
    %r = scf.while (%x = %n) : (i64) -> i64 {
      %zero = arith.constant 0 : i64
      %more = arith.cmpi ne, %x, %zero : i64
      scf.condition(%more) %x : i64
    } do {
    ^bb0(%x: i64):
      %one = arith.constant 1 : i64
      %y = arith.subi %x, %one : i64
      scf.yield %y : i64
    }
    return %r : i64
  }
  idr.func @straight(%x: i64) -> i64 {
    return %x : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
