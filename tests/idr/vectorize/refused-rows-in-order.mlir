// RUN: idris-mlir-opt %s --idr-target --idr-lower --idr-vectorize --remarks-filter=idr-vectorize 2> %t.remarks | FileCheck %s
// RUN: FileCheck %s --check-prefix=REMARK --implicit-check-not=error < %t.remarks
// RUN: idris-mlir-cc %s -o %t.o
// RUN: %cc %t.o -o %t
// RUN: %status 1 %t 2> %t.err
// RUN: FileCheck %s --check-prefix=CRASH < %t.err
// A generate whose body is a fold over an array from outside is one loop
// over rows and columns. Its fold step here divides twice, each division
// by a value that is zero at one place: the first at row 1, column 1, the
// second at row 2, column 0. The guard of a division by what may be zero
// crashes first, so the step is no body the vectorizer takes:
// idr-vectorize decides that before it changes anything and leaves the
// loop whole, still reading the whole array, and convert-linalg-to-loops
// runs it row by row, as the program does. The program ends at the first
// division. Tiled four rows at a time, it would run column 0 of the rows
// first and end at the second.
// CHECK-LABEL: func.func private @rows(
// CHECK: linalg.generic
// CHECK-SAME: iterator_types = ["parallel", "reduction"]
// CHECK-SAME: ins(%{{[^ ]+}} : memref<?xi64>)
// CHECK: return
// REMARK: remark: [Missed] Scalar
// REMARK-SAME: its body is not one the vectorizer takes
// CRASH: division by zero at Rows.idr:1:1
module attributes {idr.program} {
  func.func @root(%w: !idr.world) -> !idr.world {
    %n = arith.constant 4 : i64
    %m = arith.constant 3 : i64
    %one = arith.constant 1 : i64
    %v, %w1 = idr.array.new [%m], %one, %w : i64 -> memref<?xi64>
    %r, %w2 = func.call @rows(%n, %v, %w1) : (i64, memref<?xi64>, !idr.world) -> (memref<?xi64>, !idr.world)
    return %w2 : !idr.world
  }
  func.func private @rows(%n: i64, %v: memref<?xi64>, %w: !idr.world) -> (memref<?xi64>, !idr.world) {
    %zero = arith.constant 0 : i64
    %ten = arith.constant 10 : i64
    %eleven = arith.constant 11 : i64
    %twenty = arith.constant 20 : i64
    %r, %w1 = idr.array.generate %n, %zero, %w : i64 -> memref<?xi64> (%i: i64) {
      %w0 = idr.world.new
      %i10 = arith.muli %i, %ten : i64
      %s, %w2 = idr.array.fold %v, %zero, %w0 : memref<?xi64>, i64 -> i64 (%acc: i64, %x: i64, %j: i64) {
        %ij = arith.addi %i10, %j : i64
        %d1 = arith.subi %ij, %eleven : i64
        %d2 = arith.subi %ij, %twenty : i64
        %g1 = idr.check.nonzero %d1, "division by zero" : i64 loc("Rows.idr":1:1)
        %q1 = idr.div signed %x, %g1 : i64 loc("Rows.idr":1:1)
        %g2 = idr.check.nonzero %d2, "division by zero" : i64 loc("Rows.idr":2:1)
        %q2 = idr.div signed %x, %g2 : i64 loc("Rows.idr":2:1)
        %q = arith.addi %q1, %q2 : i64
        %t = arith.addi %acc, %q : i64
        idr.yield %t : i64
      }
      idr.yield %s : i64
    }
    return %r, %w1 : memref<?xi64>, !idr.world
  }
}
