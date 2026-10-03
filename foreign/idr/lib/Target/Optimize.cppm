// idr.target:optimize: LLVM's pipeline for the target, the same for
// executables and for idr-eval's JIT.
export module idr.target:optimize;

import idr.mlir;

export namespace idr::target {

// LLVM's O3 pipeline for the machine, with MergeFunctions: identical
// functions (clones that specialization left equal) become one.
void optimize(llvm::Module &module, llvm::TargetMachine &machine) {
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

} // namespace idr::target
