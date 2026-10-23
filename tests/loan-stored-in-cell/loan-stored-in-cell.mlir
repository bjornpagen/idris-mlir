// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics -o /dev/null
// An alias of a loan becomes no one's reference, however many times it is
// used: an op of ours that moves it into what it builds or gives adopts it,
// as one that takes it over does. A constructor given an alias as a field
// holds it in a cell, which counting then owns, so the function's verifier
// refuses it at the constructor, with a note at the loan. An op of ours
// that only reads the loan, a view of it whose result is followed as an
// alias, verifies. The two modules differ by what the op of ours does with
// the alias alone, so the refusal is the constructor's.
idr.program @loans root(@main) stage(graded) {
  idr.func @main() {
    idr.return
  }
  idr.func @size(%v: memref<?xi64>) -> i64 {
    %n = idr.lifetime -> i64 {
    ^bb0(%l: !idr.lifetime<view>):
      %bare = idr.carrier %v in %l : memref<?xi64>, !idr.lifetime<view>
      %zero = arith.constant 0 : index
      %d = memref.dim %bare, %zero : memref<?xi64>
      %tied = idr.array.tie_shape %bare dims(%d) : memref<?xi64> -> memref<?xi64>
      %e = memref.dim %tied, %zero : memref<?xi64>
      %w = arith.index_cast %e : index to i64
      idr.yield %w : i64
    }
    idr.return %n : i64
  }
}

// -----

// Held in a cell: the constructor's field is the alias.
#Box = #idr.family<"Box" [] {
    @MkBox (memref<?xi64>)
  }>
!Box = !idr.data<#Box @MkBox>
idr.program @loans root(@main) stage(graded) {
  idr.func @main() {
    idr.return
  }
  idr.func @boxes(%v: memref<?xi64>) -> !Box {
    %r = idr.lifetime -> !Box {
    ^bb0(%l: !idr.lifetime<view>):
      // expected-note @below {{}}
      %bare = idr.carrier %v in %l : memref<?xi64>, !idr.lifetime<view>
      // expected-error @below {{}}
      %box = idr.data.con(%bare : memref<?xi64>) : !Box
      idr.yield %box : !Box
    }
    idr.return %r : !Box
  }
}
