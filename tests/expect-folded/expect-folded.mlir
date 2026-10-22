// RUN: idris-mlir-opt %s --idr-expect=holds=folded=@done,word-loop=@words -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=folded=@left,word-loop=@straight -verify-diagnostics -o /dev/null
// What is left of a computation on constants, and what a loop computes
// on. @done adds an argument, which no fold can; @left adds two constants,
// which a fold replaces by their sum, and is left. @words loops over words
// alone; @straight has no loop at all.
module {
  func.func @done(%x: i64) -> i64 {
    %one = arith.constant 1 : i64
    %y = arith.addi %x, %one : i64
    return %y : i64
  }
  func.func @left() -> i64 {
    %one = arith.constant 1 : i64
    %two = arith.constant 2 : i64
    // expected-error @below {{expected folded: }}
    %three = arith.addi %one, %two : i64
    return %three : i64
  }
  func.func @words(%n: index) -> i64 {
    %zero = arith.constant 0 : index
    %step = arith.constant 1 : index
    %init = arith.constant 0 : i64
    %sum = scf.for %i = %zero to %n step %step iter_args(%acc = %init) -> (i64) {
      %w = arith.index_cast %i : index to i64
      %next = arith.addi %acc, %w : i64
      scf.yield %next : i64
    }
    return %sum : i64
  }
  // expected-error @below {{expected word-loop: }}
  func.func @straight(%x: i64) -> i64 {
    return %x : i64
  }
}
