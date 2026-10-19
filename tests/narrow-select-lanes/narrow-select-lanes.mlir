// RUN: idris-mlir-opt %s -o %t.before.mlir
// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(func.func(idr-narrow-lanes))' -o %t.after.mlir
// RUN: diff %t.before.mlir %t.after.mlir
// RUN: idris-mlir-opt %t.after.mlir --idr-expect=holds=narrowed-lanes=@pick -o /dev/null
// A vectorized loop whose only op on 64-bit lanes is a select, under a
// comparison of 32-bit lanes: a select moves lanes and costs the same at
// any width, so the loop computes on no wide lane, and idr-narrow-lanes
// gives it no version, by the one rule narrowed-lanes reads too.
func.func @pick(%a: memref<?xi32>, %b: memref<?xi32>, %out: memref<?xi64>, %n: index) {
  %c0 = arith.constant 0 : index
  %c4 = arith.constant 4 : index
  %pad = arith.constant 0 : i32
  %small = arith.constant dense<1> : vector<4xi64>
  %large = arith.constant dense<2> : vector<4xi64>
  scf.for %i = %c0 to %n step %c4 {
    %va = vector.transfer_read %a[%i], %pad {in_bounds = [true]} : memref<?xi32>, vector<4xi32>
    %vb = vector.transfer_read %b[%i], %pad {in_bounds = [true]} : memref<?xi32>, vector<4xi32>
    %lt = arith.cmpi slt, %va, %vb : vector<4xi32>
    %v = arith.select %lt, %small, %large : vector<4xi1>, vector<4xi64>
    vector.transfer_write %v, %out[%i] {in_bounds = [true]} : vector<4xi64>, memref<?xi64>
  }
  return
}
