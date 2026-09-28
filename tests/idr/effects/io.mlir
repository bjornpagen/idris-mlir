// RUN: idris-mlir-opt %s --canonicalize --cse | FileCheck %s
// Identical IO operations are neither merged nor removed, even unused.

// CHECK-LABEL: func.func @io(
// CHECK: idr.io.put_char
// CHECK-NEXT: idr.io.put_char
// CHECK-NEXT: %{{.*}}, %{{.*}} = idr.io.get_char
// CHECK-NEXT: %{{.*}}, %{{.*}} = idr.io.get_char
// CHECK-NEXT: %{{.*}}, %{{.*}} = idr.io.get_byte
// CHECK-NEXT: idr.io.exit
func.func @io(%w: !idr.world) -> !idr.world {
  %c = arith.constant 65 : i32
  %z = arith.constant 0 : i64
  %w1 = idr.io.put_char %c, %w
  %w2 = idr.io.put_char %c, %w1
  %x, %w3 = idr.io.get_char %w2
  %y, %w4 = idr.io.get_char %w3
  %b, %w5 = idr.io.get_byte %w4
  %w6 = idr.io.exit %z, %w5
  return %w : !idr.world
}
