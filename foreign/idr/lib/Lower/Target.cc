// The LLVM pipeline of executables and of idr-eval's JIT (LOW-TARGET-1).

#include "idr/Target.h"

#include "llvm/Passes/PassBuilder.h"

llvm::TargetOptions idr::targetOptions() {
  llvm::TargetOptions options;
  options.AllowFPOpFusion = llvm::FPOpFusion::Strict;
  options.FunctionSections = true;
  options.DataSections = true;
  return options;
}

void idr::optimize(llvm::Module &module, llvm::TargetMachine &machine) {
  llvm::LoopAnalysisManager lam;
  llvm::FunctionAnalysisManager fam;
  llvm::CGSCCAnalysisManager cgam;
  llvm::ModuleAnalysisManager mam;
  llvm::PipelineTuningOptions tuning;
  tuning.MergeFunctions = true;
  llvm::PassBuilder builder(&machine, tuning);
  builder.registerModuleAnalyses(mam);
  builder.registerCGSCCAnalyses(cgam);
  builder.registerFunctionAnalyses(fam);
  builder.registerLoopAnalyses(lam);
  builder.crossRegisterProxies(lam, fam, cgam, mam);
  builder.buildPerModuleDefaultPipeline(llvm::OptimizationLevel::O3).run(module, mam);
}
