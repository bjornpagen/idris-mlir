// NEEDS-ACCEPTANCE: that word-loop holds of a loop on words and fails once of @naturals, whose one loop carries a natural.
// RUN: idris-mlir-opt %s --idr-expect=holds=word-loop=@words -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=word-loop=@naturals -o /dev/null 2> %t.err
// RUN: FileCheck %s < %t.err
// RUN: grep 'error: expected ' %t.err | count 1
// A loop computes on words alone when nothing it defines or binds is a big
// or a natural (@words); one that carries a natural round computes on
// bigs (@naturals).
// CHECK-DAG: error: expected word-loop: @naturals computes on bigs in each of its loops
idr.program @words root(@root) stage(first) {
  idr.func @words(%n: index) -> i64 {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %z = arith.constant 0 : i64
    %r = scf.for %i = %c0 to %n step %c1 iter_args(%a = %z) -> (i64) {
      %x = arith.index_cast %i : index to i64
      %b = arith.addi %a, %x : i64
      scf.yield %b : i64
    }
    return %r : i64
  }
  idr.func @naturals(%n: index, %acc: !idr.nat) -> !idr.nat {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %two = idr.constant #idr.big<2> : !idr.nat
    %r = scf.for %i = %c0 to %n step %c1 iter_args(%a = %acc) -> (!idr.nat) {
      %b = idr.big.add %a, %two : !idr.nat
      scf.yield %b : !idr.nat
    }
    return %r : !idr.nat
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
