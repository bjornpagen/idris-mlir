// RUN: idris-mlir-opt %s --idr-in-bounds | FileCheck %s
// RUN: idris-mlir-opt %s --idr-in-bounds --idr-expect=holds=no-guards=@byte,no-guards=@odd,no-guards=@span,no-guards=@slot -o /dev/null
// A guard of integers goes where the ranges MLIR's integer range analysis
// gives its operands satisfy its condition wherever it runs: the low byte
// of a word is a byte; a word with its low bit set is not zero; an offset
// below 4 with 4 bytes lies in 8; an index below 8 is inside 8. A word the
// analysis knows nothing of keeps its guard. A loop's bound proves the
// guards in the loop, where it holds, and not one outside it: the counter
// the loop ends with is past the length, so a read at it keeps its guard.
// CHECK-LABEL: func.func @byte(
// CHECK-NOT: idr.check
// CHECK: return
// CHECK-LABEL: func.func @odd(
// CHECK-NOT: idr.check
// CHECK: return
// CHECK-LABEL: func.func @span(
// CHECK-NOT: idr.check
// CHECK: return
// CHECK-LABEL: func.func @slot(
// CHECK-NOT: idr.check
// CHECK: return
// CHECK-LABEL: func.func @wide(
// CHECK: idr.check.byte
// CHECK: return
// CHECK-LABEL: func.func @after(
// CHECK: scf.while
// CHECK: } do {
// CHECK-NOT: idr.check.in_bounds
// CHECK: idr.array.set
// CHECK: scf.yield
// CHECK: idr.check.in_bounds
// CHECK: idr.array.get
func.func @byte(%x: i64) -> i8 {
  %mask = arith.constant 255 : i64
  %low = arith.andi %x, %mask : i64
  %g = idr.check.byte %low, "a byte outside 0 to 255"
  %b = idr.to_byte %g
  return %b : i8
}

func.func @odd(%x: i64, %y: i64) -> i64 {
  %one = arith.constant 1 : i64
  %d = arith.ori %y, %one : i64
  %g = idr.check.nonzero %d, "division by zero" : i64
  %q = idr.div signed %x, %g : i64
  return %q : i64
}

func.func @span(%x: i64) -> i64 {
  %three = arith.constant 3 : i64
  %four = arith.constant 4 : i64
  %eight = arith.constant 8 : i64
  %at = arith.andi %x, %three : i64
  %g = idr.check.range %at, %four, %eight, "a byte range outside the buffer"
  return %g : i64
}

func.func @slot(%x: i64) -> i64 {
  %seven = arith.constant 7 : i64
  %eight = arith.constant 8 : i64
  %i = arith.andi %x, %seven : i64
  %g = idr.check.in_bounds %i, %eight, "array index out of bounds"
  return %g : i64
}

func.func @wide(%x: i64) -> i8 {
  %g = idr.check.byte %x, "a byte outside 0 to 255"
  %b = idr.to_byte %g
  return %b : i8
}

func.func @after(%n: i64, %w: !idr.world) -> (i64, !idr.world) {
  %z = arith.constant 0 : i64
  %one = arith.constant 1 : i64
  %a, %w1 = idr.array.new [%n], %z, %w : i64 -> memref<?xi64>
  %r:2 = scf.while (%i = %z, %s = %w1) : (i64, !idr.world) -> (i64, !idr.world) {
    %lo = arith.cmpi sge, %i, %z : i64
    %hi = arith.cmpi slt, %i, %n : i64
    %c = arith.andi %lo, %hi : i1
    scf.condition(%c) %i, %s : i64, !idr.world
  } do {
  ^bb0(%i: i64, %s: !idr.world):
    %c0 = arith.constant 0 : index
    %d = memref.dim %a, %c0 : memref<?xi64>
    %len = arith.index_cast %d : index to i64
    %g = idr.check.in_bounds %i, %len, "array index out of bounds"
    %s1 = idr.array.set %a[%g], %i, %s : memref<?xi64>, i64
    %j = arith.addi %i, %one overflow<nsw> : i64
    scf.yield %j, %s1 : i64, !idr.world
  }
  %e0 = arith.constant 0 : index
  %ed = memref.dim %a, %e0 : memref<?xi64>
  %elen = arith.index_cast %ed : index to i64
  %eg = idr.check.in_bounds %r#0, %elen, "array index out of bounds"
  %v, %w2 = idr.array.get %a[%eg], %r#1 : memref<?xi64> -> i64
  return %v, %w2 : i64, !idr.world
}
