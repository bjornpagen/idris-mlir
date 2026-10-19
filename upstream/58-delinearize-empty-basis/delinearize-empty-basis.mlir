// affine.delinearize_index with an empty basis and no result, in the generic
// form (the custom form cannot spell it). With the bug the generated verifier
// reads the type of the first result and asserts; without it, the verifier
// reports that the op has no result.
func.func @empty_basis(%i: index) {
  "affine.delinearize_index"(%i) <{static_basis = array<i64>}> : (index) -> ()
  return
}
