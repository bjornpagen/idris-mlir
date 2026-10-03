// idr.driver:cpu: the CPU a compilation is for, as --cpu names it.
export module idr.driver:cpu;

import idr.mlir;

import :options;

export namespace idr::driver {

// The CPU and extra features for --cpu.
struct Cpu {
  std::string name;
  std::string features;
};

// The CPU --cpu names for the target, `native` resolved. A name LLVM does
// not know is a usage error: LLVM itself would only warn and fall back to a
// generic CPU.
std::optional<Cpu> selectCpu(const llvm::Target &target, const llvm::Triple &triple) {
  Cpu cpu{targetCpu, ""};
  if (cpu.name == "native") {
    cpu.name = llvm::sys::getHostCPUName().str();
    std::vector<std::string> features;
    for (const auto &feature : llvm::sys::getHostCPUFeatures())
      features.push_back((feature.getValue() ? "+" : "-") + feature.getKey().str());
    llvm::sort(features);
    cpu.features = llvm::join(features, ",");
  }
  std::unique_ptr<llvm::MCSubtargetInfo> subtarget(
      target.createMCSubtargetInfo(triple, cpu.name, cpu.features));
  if (!subtarget || !subtarget->isCPUStringValid(cpu.name)) {
    llvm::errs() << "idris-mlir-cc: unsupported --cpu=" << targetCpu << ": " << cpu.name
                 << " is not a CPU that LLVM knows for " << triple.str()
                 << " (use native or an LLVM CPU name)\n";
    return std::nullopt;
  }
  return cpu;
}

} // namespace idr::driver
