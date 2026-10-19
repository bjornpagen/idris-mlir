// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=folded=@sum,folded=@left,folded=@computed,folded=@refused,folded=@calls -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=folded=@left,folded=@computed -verify-diagnostics -o /dev/null
// No op is left that a fold would have replaced by constants: arithmetic
// over constants alone folds (@sum, and the sum @left adds to its
// parameter), and arithmetic on a parameter has nothing to fold
// (@computed). As written, @left's sum of two constants is left. What
// may not fold is not asked to: a guard that refuses its constant, which
// must crash where it runs (@refused), and a call, even of constants
// (@calls).
idr.program @folded root(@root) stage(first) {
  idr.func @sum() -> i64 {
    %two = arith.constant 2 : i64
    %three = arith.constant 3 : i64
    %five = arith.addi %two, %three : i64
    %r = arith.muli %five, %five : i64
    return %r : i64
  }
  idr.func @left(%y: i64) -> i64 {
    %two = arith.constant 2 : i64
    %three = arith.constant 3 : i64
    // expected-error @below {{expected folded: }}
    %five = arith.addi %two, %three : i64
    %r = arith.addi %five, %y : i64
    return %r : i64
  }
  idr.func @computed(%x: i64) -> i64 {
    %r = arith.muli %x, %x : i64
    return %r : i64
  }
  idr.func @refused() -> i64 {
    %zero = arith.constant 0 : i64
    %seven = arith.constant 7 : i64
    %g = idr.check.nonzero %zero, "division by zero" : i64
    %q = idr.divs %seven, %g : i64
    return %q : i64
  }
  idr.func @calls() -> i64 {
    %two = arith.constant 2 : i64
    %r = idr.call @computed(%two) : (i64) -> i64
    return %r : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
