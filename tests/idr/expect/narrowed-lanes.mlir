// NEEDS-ACCEPTANCE: that narrowed-lanes holds of a loop computing on 32-bit lanes beside its accumulation, and fails once of @scalar, which has no loop on lanes at all, on any target.
// RUN: idris-mlir-opt %s --idr-expect=holds=narrowed-lanes=@squares -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=narrowed-lanes=@scalar -o /dev/null 2> %t.err
// RUN: FileCheck %s < %t.err
// RUN: grep 'error: expected ' %t.err | count 1
// After idr-narrow-lanes some loop computes its integer lanes in 32 bits:
// @squares' products are lanes of i32, beside the sum it carries round,
// which is no lane. A function with no such loop fails whatever the target.
// A lowered module, of func.func, as idr-narrow-lanes leaves one.
// CHECK-DAG: error: expected narrowed-lanes: no loop computes integer lanes in 32 bits in @scalar
module {
  func.func @squares(%n: index, %v: vector<4xi32>, %z: vector<4xi32>) -> vector<4xi32> {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %r = scf.for %i = %c0 to %n step %c1 iter_args(%a = %z) -> (vector<4xi32>) {
      %s = arith.muli %v, %v : vector<4xi32>
      %b = arith.addi %a, %s : vector<4xi32>
      scf.yield %b : vector<4xi32>
    }
    return %r : vector<4xi32>
  }
  func.func @scalar(%x: i64) -> i64 {
    %y = arith.addi %x, %x : i64
    return %y : i64
  }
}
