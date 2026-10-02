// RUN: idris-mlir-opt %s --idr-narrow-lanes | FileCheck %s
// idr-narrow-lanes versions a loop only when its ops say it is vectorized:
// vector ops, the loops of its tiles, and ops with neither effects nor
// regions. The loop that squares its indices on vector lanes gets a version
// on 32-bit lanes; the same loop holding a tile the vectorizer left scalar
// (a linalg.generic, which writes its tile element by element) gets none
// and keeps its 64-bit lanes.
// CHECK-LABEL: func.func @vectorized(
// CHECK: scf.if
// CHECK: arith.muli {{.*}} : vector<4xi32>
// CHECK: } else {
// CHECK: arith.muli {{.*}} : vector<4xi64>
// CHECK: return
// CHECK-LABEL: func.func @mixed(
// CHECK-NOT: scf.if
// CHECK: arith.muli {{.*}} : vector<4xi64>
// CHECK: linalg.generic
// CHECK-NOT: scf.if
// CHECK: return
#map = affine_map<(d0) -> (d0)>
module {
  func.func @vectorized(%a: memref<?xi64>, %n: index) {
    %c0 = arith.constant 0 : index
    %c4 = arith.constant 4 : index
    scf.for %i = %c0 to %n step %c4 {
      %step = vector.step : vector<4xindex>
      %base = vector.broadcast %i : index to vector<4xindex>
      %at = arith.addi %base, %step : vector<4xindex>
      %w = arith.index_cast %at : vector<4xindex> to vector<4xi64>
      %sq = arith.muli %w, %w : vector<4xi64>
      vector.transfer_write %sq, %a[%i] {in_bounds = [true]} : vector<4xi64>, memref<?xi64>
    }
    return
  }
  func.func @mixed(%a: memref<?xi64>, %b: memref<?xi64>, %n: index) {
    %c0 = arith.constant 0 : index
    %c4 = arith.constant 4 : index
    scf.for %i = %c0 to %n step %c4 {
      %step = vector.step : vector<4xindex>
      %base = vector.broadcast %i : index to vector<4xindex>
      %at = arith.addi %base, %step : vector<4xindex>
      %w = arith.index_cast %at : vector<4xindex> to vector<4xi64>
      %sq = arith.muli %w, %w : vector<4xi64>
      vector.transfer_write %sq, %a[%i] {in_bounds = [true]} : vector<4xi64>, memref<?xi64>
      %tile = memref.subview %b[%i] [4] [1] : memref<?xi64> to memref<4xi64, strided<[1], offset: ?>>
      linalg.generic {indexing_maps = [#map], iterator_types = ["parallel"]}
          outs(%tile : memref<4xi64, strided<[1], offset: ?>>) {
      ^bb0(%out: i64):
        %k = linalg.index 0 : index
        %x = arith.index_cast %k : index to i64
        linalg.yield %x : i64
      }
    }
    return
  }
}
