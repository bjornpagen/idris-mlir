// idr.target:targetoptions: LLVM's options for the target, the same for
// executables and for idr-eval's JIT.
export module idr.target:targetoptions;

import idr.mlir;

export namespace idr::target {

// No fast-math and no FP contraction anywhere:
// `+` and `*` are IEEE operations, never fused.
llvm::TargetOptions targetOptions() {
  llvm::TargetOptions options;
  options.AllowFPOpFusion = llvm::FPOpFusion::Strict;
  options.FunctionSections = true;
  options.DataSections = true;
  return options;
}

// The machine a program, or the runtime prepared for every program, is
// compiled for: those options, position-independent, optimized as far as
// LLVM goes. The triple, CPU and features are the module's target. Null
// when LLVM has no machine for them.
std::unique_ptr<llvm::TargetMachine> machine(const llvm::Target &target, const llvm::Triple &triple,
                                             llvm::StringRef cpu, llvm::StringRef features) {
  return std::unique_ptr<llvm::TargetMachine>(target.createTargetMachine(
      triple, cpu, features, targetOptions(), llvm::Reloc::PIC_, std::nullopt,
      llvm::CodeGenOptLevel::Aggressive));
}

} // namespace idr::target
