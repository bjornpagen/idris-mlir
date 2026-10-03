// idr.target:vectors: the width of the target's vector registers.
export module idr.target:vectors;

import idr.mlir;

using namespace mlir;

export namespace idr::target {

// The width of the target's vector registers in bits, read from the
// module's `#llvm.target` (the one place the target is decided): 256 on
// x86-64 with AVX (x86-64-v3), 512 with AVX-512, else 128 (SSE2, NEON). A
// module without a target computes on 128. What idr-vectorize tiles a
// parallel dimension by, over the width of the words it computes.
unsigned vectorBits(ModuleOp module) {
  auto target = module->getAttrOfType<LLVM::TargetAttr>(LLVM::LLVMDialect::getTargetAttrName());
  if (!target)
    return 128;
  LLVM::TargetFeaturesAttr features = target.getFeatures();
  auto has = [&](StringRef feature) { return features && features.contains(feature); };
  if (llvm::Triple(target.getTriple().getValue()).isX86())
    return has("+avx512f") ? 512 : has("+avx") ? 256 : 128;
  return 128;
}

} // namespace idr::target
