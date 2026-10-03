// idr.driver:isprepared: whether a runtime module is the prepared runtime.
export module idr.driver:isprepared;

import idr.mlir;

import :marks;

export namespace idr::driver {

// Whether a runtime module is what --prepare-runtime wrote.
bool isPrepared(const llvm::Module &module) {
  return module.getModuleFlag(preparedCpuFlag) && module.getModuleFlag(preparedFeaturesFlag);
}

} // namespace idr::driver
