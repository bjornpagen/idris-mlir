// NEEDS-ACCEPTANCE: that vectorized holds of a function computing on vectors, and that the -verify-diagnostics run passes: @scalar fails at its scalar linalg.generic over words, and at the function for computing on no vector at all.
// RUN: idris-mlir-opt %s --idr-expect=holds=vectorized=@lanes -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=vectorized=@scalar -verify-diagnostics -o /dev/null
// After the vectorization schedule a loop computes on vectors (@lanes),
// and no loop over words with a parallel dimension is left scalar, as
// @scalar's linalg.generic is. A lowered module, of func.func.
#map = affine_map<(d0) -> (d0)>
module {
  func.func @lanes(%x: i64) -> i64 {
    %v = vector.broadcast %x : i64 to vector<4xi64>
    %s = vector.reduction <add>, %v : vector<4xi64> into i64
    return %s : i64
  }
  // expected-error @below {{expected vectorized: no loop computes on vectors in @scalar}}
  func.func @scalar(%x: tensor<?xi64>) -> tensor<?xi64> {
    %c0 = arith.constant 0 : index
    %n = tensor.dim %x, %c0 : tensor<?xi64>
    %e = tensor.empty(%n) : tensor<?xi64>
    // expected-error @below {{expected vectorized: a loop over words with a parallel dimension stayed scalar in @scalar}}
    %y = linalg.generic {indexing_maps = [#map, #map], iterator_types = ["parallel"]}
        ins(%x : tensor<?xi64>) outs(%e : tensor<?xi64>) {
    ^bb0(%a: i64, %b: i64):
      %s = arith.addi %a, %a : i64
      linalg.yield %s : i64
    } -> tensor<?xi64>
    return %y : tensor<?xi64>
  }
}
