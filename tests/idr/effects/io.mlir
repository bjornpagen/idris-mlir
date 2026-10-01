// RUN: idris-mlir-opt %s --canonicalize --cse | FileCheck %s
// Identical IO operations are neither merged nor removed, even unused.

// CHECK-LABEL: func.func @io(
// CHECK: idr.io.put_char
// CHECK-NEXT: idr.io.put_char
// CHECK-NEXT: %{{.*}}, %{{.*}} = idr.io.get_byte
// CHECK-NEXT: %{{.*}}, %{{.*}} = idr.io.get_byte
func.func @io(%w: !idr.world) -> !idr.world {
  %c = arith.constant 65 : i32
  %w1 = idr.io.put_char %c, %w
  %w2 = idr.io.put_char %c, %w1
  %x, %w3 = idr.io.get_byte %w2
  %y, %w4 = idr.io.get_byte %w3
  return %w : !idr.world
}

// A forged world (a trusted library's unsafePerformIO) starts a chain of
// its own; two of them are two, however alike, and neither is removed, nor
// the IO on them: the effects order them where no world does.
// CHECK-LABEL: func.func @forged(
// CHECK: idr.world.new
// CHECK-NEXT: idr.io.put_char
// CHECK-NEXT: idr.world.new
// CHECK-NEXT: idr.io.put_char
func.func @forged(%c: i32) {
  %w = idr.world.new
  %w1 = idr.io.put_char %c, %w
  %v = idr.world.new
  %v1 = idr.io.put_char %c, %v
  return
}
