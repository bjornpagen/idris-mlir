// cse on a linalg.generic nested in the body of another: three linalg.index
// ops, two of the outer generic (%i, %i2: one value) and one of the inner
// (%j, the inner iteration index). With the bug, cse replaces %j by %i and
// one linalg.index is left; without it, two are.
#map = affine_map<(d0) -> (d0)>
func.func @nested(%n: index, %m: index) -> tensor<?xindex> {
  %e = tensor.empty(%n) : tensor<?xindex>
  %r = linalg.generic {indexing_maps = [#map], iterator_types = ["parallel"]} outs(%e : tensor<?xindex>) {
  ^bb0(%out: index):
    %i = linalg.index 0 : index
    %i2 = linalg.index 0 : index
    %ie = tensor.empty(%m) : tensor<?xindex>
    %inner = linalg.generic {indexing_maps = [#map], iterator_types = ["parallel"]} outs(%ie : tensor<?xindex>) {
    ^bb1(%o: index):
      %j = linalg.index 0 : index
      linalg.yield %j : index
    } -> tensor<?xindex>
    %c0 = arith.constant 0 : index
    %x = tensor.extract %inner[%c0] : tensor<?xindex>
    %s = arith.addi %i, %x : index
    %t = arith.addi %s, %i2 : index
    linalg.yield %t : index
  } -> tensor<?xindex>
  return %r : tensor<?xindex>
}
