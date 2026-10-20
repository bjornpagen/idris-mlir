// RUN: idris-mlir-opt %s --idr-expect=holds=word-loop=@words,word-loop=@outside -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=word-loop=@naturals -verify-diagnostics -o /dev/null
// A loop computes on words alone when nothing it defines or binds is a big
// or a natural (@words); one that carries a natural round computes on
// bigs (@naturals). A natural the function uses outside its loop is no
// value of the loop (@outside).
idr.program @words root(@root) stage(first) types #idr.types<> {
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
  // expected-error @below {{expected word-loop: }}
  idr.func @naturals(%n: index, %acc: !idr.nat) -> !idr.nat {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %two = idr.constant !idr.nat #idr.big<2>
    %r = scf.for %i = %c0 to %n step %c1 iter_args(%a = %acc) -> (!idr.nat) {
      %b = idr.big.add %a, %two : !idr.nat
      scf.yield %b : !idr.nat
    }
    return %r : !idr.nat
  }
  idr.func @outside(%n: index, %acc: !idr.nat) -> (i64, !idr.nat) {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %z = arith.constant 0 : i64
    %two = idr.constant !idr.nat #idr.big<2>
    %m = idr.big.add %acc, %two : !idr.nat
    %r = scf.for %i = %c0 to %n step %c1 iter_args(%a = %z) -> (i64) {
      %x = arith.index_cast %i : index to i64
      %b = arith.addi %a, %x : i64
      scf.yield %b : i64
    }
    return %r, %m : i64, !idr.nat
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
