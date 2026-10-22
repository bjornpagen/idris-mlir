// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=folded=@f -o /dev/null
// What the test checks, in a sentence, stated as properties idr-expect
// checks rather than as the ops that happen to show them. A module is one
// idr.program, which names its root, of type () -> i64, and its stage
// (higher before the closures become sums, first after it, then graded,
// owned and lowered). A data type is the family it is, written where it
// occurs: !idr.data<#Family[indices]>.
idr.program @fixture root(@f) stage(first) {
  idr.func @f() -> i64 {
    %two = arith.constant 2 : i64
    %four = arith.addi %two, %two : i64
    return %four : i64
  }
}
