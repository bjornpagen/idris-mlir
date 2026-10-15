// RUN: idris-mlir-opt %s --int-range-optimizations | FileCheck %s
// RUN: idris-mlir-opt %s --idr-narrow | FileCheck %s
// Range analysis asks every idr.constant for its range: a big or a
// natural has its value's, and a constant that is no integer states none,
// which leaves it as it is.
// CHECK-LABEL: idr.func private @text(
// CHECK: constant "x" : !idr.str
// CHECK-LABEL: idr.func private @numbers(
// CHECK: idr.big.cmp lt
module {
  idr.func private @text() -> !idr.str {
    %0 = idr.constant "x" : !idr.str
    return %0 : !idr.str
  }
  idr.func private @numbers(%n: !idr.nat) -> i1 {
    %big = idr.constant #idr.big<"100000000000000000000000"> : !idr.nat
    %c = idr.big.cmp lt %n, %big : !idr.nat
    return %c : i1
  }
}
