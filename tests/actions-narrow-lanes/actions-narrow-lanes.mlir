// RUN: idris-mlir-opt %s -o %t.none.mlir
// RUN: idris-mlir-opt %s --idr-narrow-lanes --mlir-disable-threading -mlir-debug-counter=idr-narrow-lanes-version-count=0 -o %t.skipped.mlir
// RUN: diff %t.none.mlir %t.skipped.mlir
// RUN: idris-mlir-opt %s --idr-narrow-lanes -o %t.done.mlir
// RUN: %status 1 diff %t.none.mlir %t.done.mlir
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
  func.func @once(%a: memref<?xi64>, %n: index) {
    %c4 = arith.constant 4 : index
    %last = affine.apply affine_map<()[s0] -> (s0 - s0 mod 4)>()[%n]
    scf.for %i = %last to %n step %c4 {
      %step = vector.step : vector<4xindex>
      %base = vector.broadcast %i : index to vector<4xindex>
      %at = arith.addi %base, %step : vector<4xindex>
      %w = arith.index_cast %at : vector<4xindex> to vector<4xi64>
      %sq = arith.muli %w, %w : vector<4xi64>
      vector.transfer_write %sq, %a[%i] {in_bounds = [true]} : vector<4xi64>, memref<?xi64>
    }
    return
  }
  func.func @shifted(%a: memref<?xi64>, %n: index) {
    %c0 = arith.constant 0 : index
    %c4 = arith.constant 4 : index
    %c41 = arith.constant dense<41> : vector<4xi64>
    scf.for %i = %c0 to %n step %c4 {
      %step = vector.step : vector<4xindex>
      %base = vector.broadcast %i : index to vector<4xindex>
      %at = arith.addi %base, %step : vector<4xindex>
      %w = arith.index_cast %at : vector<4xindex> to vector<4xi64>
      %s = arith.remui %w, %c41 : vector<4xi64>
      %r = arith.shrui %w, %s : vector<4xi64>
      vector.transfer_write %r, %a[%i] {in_bounds = [true]} : vector<4xi64>, memref<?xi64>
    }
    return
  }
  func.func @unsigned(%a: memref<?xi64>, %n: index) {
    %c0 = arith.constant 0 : index
    %c4 = arith.constant 4 : index
    %c2 = arith.constant dense<2> : vector<4xi64>
    %c7 = arith.constant dense<7> : vector<4xi64>
    scf.for %i = %c0 to %n step %c4 {
      %step = vector.step : vector<4xindex>
      %base = vector.broadcast %i : index to vector<4xindex>
      %at = arith.addi %base, %step : vector<4xindex>
      %w = arith.index_cast %at : vector<4xindex> to vector<4xi64>
      %x = arith.subi %w, %c2 : vector<4xi64>
      %r = arith.remui %x, %c7 : vector<4xi64>
      vector.transfer_write %r, %a[%i] {in_bounds = [true]} : vector<4xi64>, memref<?xi64>
    }
    return
  }
}
