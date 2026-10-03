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

} // namespace idr::target
