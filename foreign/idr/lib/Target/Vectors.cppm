// idr.target:vectors: the width of the target's vector registers.
export module idr.target:vectors;

import idr.mlir;

export namespace idr::target {

// The width of the target's vector registers in bits, read from the
// module's `#llvm.target` (the one place the target is decided): 256 on
// x86-64 with AVX (x86-64-v3), 512 with AVX-512, else 128 (SSE2, NEON). A
// module without a target computes on 128. What idr-vectorize tiles a
// parallel dimension by, over the width of the words it computes.
unsigned vectorBits(mlir::ModuleOp module);

} // namespace idr::target
