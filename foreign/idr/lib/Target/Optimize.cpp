// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// LLVM's side of the target: the machine a program is compiled for, and
// LLVM's pipeline for it.

#include "idr/Target/Target.h"

#include "idr/Support/Profile.h"

#include "llvm/ADT/Twine.h"
#include "llvm/Analysis/CGSCCPassManager.h"
#include "llvm/Analysis/LoopAnalysisManager.h"
#include "llvm/IR/Module.h"
#include "llvm/IR/PassManager.h"
#include "llvm/MC/TargetRegistry.h"
#include "llvm/Passes/PassBuilder.h"
#include "llvm/Support/CodeGen.h"
#include "llvm/Target/TargetOptions.h"
#include "llvm/TargetParser/Triple.h"

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

llvm::Expected<std::unique_ptr<llvm::TargetMachine>>
idr::target::machine(const llvm::Target &target) {
  std::unique_ptr<llvm::TargetMachine> made(target.createTargetMachine(
      llvm::Triple(triple), programCpu.name, programCpu.features, targetOptions(),
      llvm::Reloc::PIC_, std::nullopt, llvm::CodeGenOptLevel::Aggressive));
  if (!made)
    return llvm::createStringError(llvm::Twine("LLVM has no target machine for ") + triple +
                                   " (" + programCpu.name + ")");
  return made;
}

void idr::target::optimize(llvm::Module &module, llvm::TargetMachine &machine) {
  llvm::LoopAnalysisManager lam;
  llvm::FunctionAnalysisManager fam;
  llvm::CGSCCAnalysisManager cgam;
  llvm::ModuleAnalysisManager mam;
  llvm::PipelineTuningOptions tuning;
  tuning.MergeFunctions = true;
  // Every pass and analysis of the pipeline is a zone of the trace, when
  // one is started; the callbacks are null until then.
  llvm::PassBuilder builder(&machine, tuning, std::nullopt, idr::profile::llvmCallbacks());
  builder.registerModuleAnalyses(mam);
  builder.registerCGSCCAnalyses(cgam);
  builder.registerFunctionAnalyses(fam);
  builder.registerLoopAnalyses(lam);
  builder.crossRegisterProxies(lam, fam, cgam, mam);
  builder.buildPerModuleDefaultPipeline(llvm::OptimizationLevel::O3).run(module, mam);
}
