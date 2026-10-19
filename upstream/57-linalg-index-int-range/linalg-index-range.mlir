// int-range-optimizations on comparisons of linalg.index: the index of a
// loop of static extent 8 is below 8, and every index is non-negative, so
// both comparisons fold to true. With no range for linalg.index both stay;
// the same comparisons of an scf.for induction variable fold.
#map = affine_map<(d0) -> (d0)>
func.func @static(%t: tensor<8xi1>) -> tensor<8xi1> {
  %c8 = arith.constant 8 : index
  %r = linalg.generic {indexing_maps = [#map], iterator_types = ["parallel"]} outs(%t : tensor<8xi1>) {
  ^bb0(%out: i1):
    %i = linalg.index 0 : index
    %below = arith.cmpi ult, %i, %c8 : index
    linalg.yield %below : i1
  } -> tensor<8xi1>
  return %r : tensor<8xi1>
}
func.func @dynamic(%t: tensor<?xi1>) -> tensor<?xi1> {
  %c0 = arith.constant 0 : i64
  %r = linalg.generic {indexing_maps = [#map], iterator_types = ["parallel"]} outs(%t : tensor<?xi1>) {
  ^bb0(%out: i1):
    %i = linalg.index 0 : index
    %w = arith.index_castui %i : index to i64
    %nonneg = arith.cmpi sge, %w, %c0 : i64
    linalg.yield %nonneg : i1
  } -> tensor<?xi1>
  return %r : tensor<?xi1>
}
