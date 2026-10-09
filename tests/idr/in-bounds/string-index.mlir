// RUN: idris-mlir-opt %s --idr-in-bounds | FileCheck %s
// RUN: idris-mlir-opt %s --idr-in-bounds --idr-expect=holds=no-guards=@inside -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-in-bounds --idr-expect=holds=no-guards=@anywhere -o /dev/null 2> %t.err
// RUN: FileCheck %s --check-prefix=LEFT < %t.err
// The guard of a string's index is proven as an array's is, by what the
// path to it says of the index and the length it is checked against: a
// read on the path where the index is at least 0 and below the string's
// length needs no guard. A read anywhere keeps it.
// CHECK-LABEL: func.func @inside(
// CHECK-NOT: idr.check.in_bounds
// CHECK: idr.str.index
// CHECK: return
// CHECK-LABEL: func.func @anywhere(
// CHECK: idr.check.in_bounds
// CHECK: idr.str.index
// LEFT: error: expected no-guards: idr.check.in_bounds is left in @anywhere
func.func @inside(%s: !idr.str, %i: i64) -> i32 {
  %zero = arith.constant 0 : i64
  %none = arith.constant 0 : i32
  %len = idr.str.length %s
  %low = arith.cmpi sge, %i, %zero : i64
  %below = arith.cmpi slt, %i, %len : i64
  %ok = arith.andi %low, %below : i1
  %r = scf.if %ok -> i32 {
    %g = idr.check.in_bounds %i, %len, "string index out of range"
    %c = idr.str.index %s, %g
    scf.yield %c : i32
  } else {
    scf.yield %none : i32
  }
  return %r : i32
}

func.func @anywhere(%s: !idr.str, %i: i64) -> i32 {
  %len = idr.str.length %s
  %g = idr.check.in_bounds %i, %len, "string index out of range"
  %c = idr.str.index %s, %g
  return %c : i32
}
