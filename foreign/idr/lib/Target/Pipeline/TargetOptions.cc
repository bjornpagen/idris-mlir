// LLVM's options for the target.
module idr.target;

import idr.mlir;

llvm::TargetOptions idr::target::targetOptions() {
  llvm::TargetOptions options;
  options.AllowFPOpFusion = llvm::FPOpFusion::Strict;
  options.FunctionSections = true;
  options.DataSections = true;
  return options;
}
