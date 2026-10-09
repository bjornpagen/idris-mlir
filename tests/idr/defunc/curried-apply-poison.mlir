// RUN: idris-mlir-opt %s --idr-defunctionalize > %t.mlir
// RUN: FileCheck %s --implicit-check-not=idr.apply < %t.mlir
// A closure no label reaches is a value the program never has: an apply of
// it runs nowhere, and its results are poison. A curried apply, whose
// result is applied in turn, gives a closure no label reaches either, so
// that apply is poison too, and nothing is left to apply.
// CHECK-LABEL: func.func private @both(
// CHECK: %[[R:.*]] = ub.poison : i64
// CHECK: return %[[R]] : i64
module attributes {idr.program} {
  func.func private @both(%f: !idr.fn<(i64) -> (!idr.fn<(i64) -> (i64)>)>, %x: i64, %y: i64) -> i64 {
    %g = idr.apply %f(%x) : !idr.fn<(i64) -> (!idr.fn<(i64) -> (i64)>)>
    %r = idr.apply %g(%y) : !idr.fn<(i64) -> (i64)>
    return %r : i64
  }
  func.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}
