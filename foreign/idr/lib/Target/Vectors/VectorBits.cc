// The width of the target's vector registers.
module idr.target;

import idr.mlir;

using namespace mlir;

unsigned idr::target::vectorBits(ModuleOp module) {
  auto target = module->getAttrOfType<LLVM::TargetAttr>(LLVM::LLVMDialect::getTargetAttrName());
  if (!target)
    return 128;
  LLVM::TargetFeaturesAttr features = target.getFeatures();
  auto has = [&](StringRef feature) { return features && features.contains(feature); };
  if (llvm::Triple(target.getTriple().getValue()).isX86())
    return has("+avx512f") ? 512 : has("+avx") ? 256 : 128;
  return 128;
}
