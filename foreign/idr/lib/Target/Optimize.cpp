// LLVM's side of the target: the machine a program is compiled for, and
// LLVM's pipeline for it.

#include "idr/Target/Target.h"

#include "llvm/Analysis/CGSCCPassManager.h"
#include "llvm/Analysis/LoopAnalysisManager.h"
#include "llvm/IR/Module.h"
#include "llvm/IR/PassManager.h"
#include "llvm/MC/TargetRegistry.h"
#include "llvm/Passes/PassBuilder.h"
#include "llvm/Support/CodeGen.h"
#include "llvm/Target/TargetOptions.h"

#include <memory>
#include <optional>

// No fast-math and no FP contraction anywhere: `+` and `*` are IEEE
// operations, never fused. LLVM fuses a multiply and an add only where the
// IR allows it, an operation with the `contract` flag or a call of
// llvm.fmuladd (which the vector dialect makes of vector.fma), and neither
// the lowering nor the runtime (-ffp-contract=off) writes either, so no
// option says it.
static llvm::TargetOptions targetOptions() {
  llvm::TargetOptions options;
  options.FunctionSections = true;
  options.DataSections = true;
  return options;
}

std::unique_ptr<llvm::TargetMachine> idr::target::machine(const llvm::Target &target,
                                                          const llvm::Triple &triple,
                                                          llvm::StringRef cpu,
                                                          llvm::StringRef features) {
  return std::unique_ptr<llvm::TargetMachine>(target.createTargetMachine(
      triple, cpu, features, targetOptions(), llvm::Reloc::PIC_, std::nullopt,
      llvm::CodeGenOptLevel::Aggressive));
}

void idr::target::optimize(llvm::Module &module, llvm::TargetMachine &machine) {
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
