// idr.driver:retarget: runtime code, raised to the program's CPU.
export module idr.driver:retarget;

import idr.mlir;

import :marks;

export namespace idr::driver {

// Runtime code was compiled for the target's baseline, plus the
// features a function asks for itself (a simdutf kernel's AVX2, say). It takes
// the program's CPU and keeps every feature it asked for, so it inlines into
// program code and no function loses an instruction it relies on; the
// baseline functions keep the baseline. A prepared function remembers what
// it asked for in its marks, which the archive's functions still carry as
// their attributes; the marks are read off here.
void retarget(llvm::Module &module, const llvm::TargetMachine &machine) {
  llvm::StringRef cpuFeatures = machine.getTargetFeatureString();
  for (llvm::Function &function : module) {
    if (function.isDeclaration() || !function.hasFnAttribute("target-cpu"))
      continue;
    // PIN(clang-module-predeclared-new) — see PINS.md
    llvm::SmallString<256> features(
        function.getFnAttribute(function.hasFnAttribute(featuresMark) ? featuresMark
                                                                      : "target-features")
            .getValueAsString());
    function.removeFnAttr(cpuMark);
    function.removeFnAttr(featuresMark);
    if (function.hasFnAttribute(baselineMark))
      continue;
    if (!cpuFeatures.empty()) {
      llvm::SmallString<256> own = features;
      features = cpuFeatures;
      if (!own.empty()) {
        features += ",";
        features += own;
      }
    }
    function.addFnAttr("target-cpu", machine.getTargetCPU());
    function.removeFnAttr("tune-cpu");
    if (features.empty())
      function.removeFnAttr("target-features");
    else
      function.addFnAttr("target-features", features);
  }
}

} // namespace idr::driver
