// RUN: idris-mlir-opt %s --int-range-optimizations | FileCheck %s
// RUN: idris-mlir-opt %s --idr-rc --idr-narrow | FileCheck %s
// NEEDS-ACCEPTANCE: the input is a program of the first stage, which idr-rc counts first: at the owned stage every reference of ours is graded (R04), so the checks are of the counted program; confirm them against it.
// Range analysis asks every idr.constant for its range: a big or a
// natural has its value's, and a constant that is no integer states none,
// which leaves it as it is.
// CHECK-LABEL: idr.func @text(
// CHECK: constant "x" : !idr.str
// CHECK-LABEL: idr.func @numbers(
// CHECK: idr.big.cmp lt
idr.program @constants root(@root) stage(first) {
  idr.func @text() -> !idr.str {
    %0 = idr.constant "x" : !idr.str
    return %0 : !idr.str
  }
  idr.func @numbers(%n: !idr.nat) -> i1 {
    %big = idr.constant #idr.big<100000000000000000000000> : !idr.nat
    %c = idr.big.cmp lt %n, %big : !idr.nat
    return %c : i1
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
