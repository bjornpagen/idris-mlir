// RUN: idris-mlir-opt %s --int-range-optimizations | FileCheck %s
// Tags, characters and lengths have known ranges, which
// upstream's integer range optimizations use.

idr.data @T {
  idr.ctor @A ()
  idr.ctor @B ()
  idr.ctor @C ()
}

// CHECK-LABEL: func.func @ranges(
// CHECK-DAG: %[[TRUE:.*]] = arith.constant true
// CHECK: return %[[TRUE]], %[[TRUE]], %[[TRUE]], %[[TRUE]], %[[TRUE]], %[[TRUE]]
func.func @ranges(%t: !idr.data<@T>, %x: i64, %u: i8, %d: f64, %s: !idr.str)
    -> (i1, i1, i1, i1, i1, i1) {
  %three = arith.constant 3 : i64
  %tag = idr.tag %t : !idr.data<@T>
  %a = arith.cmpi ult, %tag, %three : i64
  %max = arith.constant 1114111 : i32
  %ch = idr.to_char signed %x : i64
  %b = arith.cmpi ule, %ch, %max : i32
  %zero = arith.constant 48 : i32
  %minus = arith.constant 45 : i32
  %plus = arith.constant 43 : i32
  %ih = idr.int_head signed %x : i64
  %c = arith.cmpi sge, %ih, %minus : i32
  %uh = idr.int_head %u : i8
  %e = arith.cmpi sge, %uh, %zero : i32
  %dh = idr.double_head %d
  %f = arith.cmpi sge, %dh, %plus : i32
  %len = idr.str.length %s
  %z = arith.constant 0 : i64
  %g = arith.cmpi sge, %len, %z : i64
  return %a, %b, %c, %e, %f, %g : i1, i1, i1, i1, i1, i1
}
