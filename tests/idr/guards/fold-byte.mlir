// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s
// The guard of an Int written as a byte folds to the Int where it is a
// constant from 0 to 255; then the byte folds too. Above 255, or below 0,
// the guard stays, to crash where it runs. A guard of what an identical
// guard already checked folds too.
// CHECK-LABEL: func.func @proving(
// CHECK-NOT: idr.check.byte
// CHECK-NOT: idr.to_byte
// CHECK: %[[B:.*]] = arith.constant -1 : i8
// CHECK: return %[[B]]
func.func @proving() -> i8 {
  %x = arith.constant 255 : i64
  %g = idr.check.byte %x, "a byte outside 0 to 255"
  %b = idr.to_byte %g
  return %b : i8
}

// CHECK-LABEL: func.func @failing(
// CHECK: idr.check.byte %{{.*}}, "a byte outside 0 to 255"
// CHECK: idr.check.byte %{{.*}}, "a byte outside 0 to 255"
// CHECK: return
func.func @failing() -> (i8, i8) {
  %above = arith.constant 256 : i64
  %g = idr.check.byte %above, "a byte outside 0 to 255"
  %b = idr.to_byte %g
  %below = arith.constant -1 : i64
  %h = idr.check.byte %below, "a byte outside 0 to 255"
  %c = idr.to_byte %h
  return %b, %c : i8, i8
}

// CHECK-LABEL: func.func @again(
// CHECK-SAME: %[[X:[^:]*]]: i64)
// CHECK: %[[G:.*]] = idr.check.byte %[[X]], "a byte outside 0 to 255"
// CHECK-NOT: idr.check.byte
// CHECK: idr.to_byte %[[G]]
// CHECK-NOT: idr.check.byte
// CHECK: idr.to_byte %[[G]]
// CHECK-NOT: idr.check.byte
// CHECK: return
func.func @again(%x: i64) -> (i8, i8) {
  %g = idr.check.byte %x, "a byte outside 0 to 255"
  %b = idr.to_byte %g
  %h = idr.check.byte %g, "a byte outside 0 to 255"
  %c = idr.to_byte %h
  return %b, %c : i8, i8
}
