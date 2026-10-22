// mlir-opt memref-noalias.mlir -convert-func-to-llvm
//
// At the pin the lowered function's seven arguments carry no attribute:
// llvm.noalias is dropped with the memref's expansion into its descriptor.
// With the patch, the allocated and the aligned pointer carry it.
func.func @update(%buffer: memref<?xf32> {llvm.noalias}, %i: index, %v: f32) {
  memref.store %v, %buffer[%i] : memref<?xf32>
  return
}
