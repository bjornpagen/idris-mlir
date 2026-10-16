// NEEDS-ACCEPTANCE: that folded holds of every function once --canonicalize has folded the arithmetic over constants, and fails once of @left as written, at its arith.addi of two constants.
// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=folded=@sum,folded=@left,folded=@computed -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=folded=@left,folded=@computed -o /dev/null 2> %t.err
// RUN: FileCheck %s < %t.err
// RUN: grep 'error: expected ' %t.err | count 1
// No op is left that a fold would have replaced by constants: arithmetic
// over constants alone folds (@sum, and the sum @left adds to its
// parameter), and arithmetic on a parameter has nothing to fold
// (@computed). As written, @left's sum of two constants is left.
// CHECK-DAG: error: expected folded: {{.*}} in @left computes from constants alone and is left unfolded
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
    %five = arith.addi %two, %three : i64
    %r = arith.addi %five, %y : i64
    return %r : i64
  }
  idr.func @computed(%x: i64) -> i64 {
    %r = arith.muli %x, %x : i64
    return %r : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
