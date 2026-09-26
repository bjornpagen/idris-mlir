// idris-mlir-cc: runs OPT-PIPE-1 in process, from idr contract text to an
// object file (DRV-CC-1, DRV-CC-2, LOW-TARGET-1).

#include "idr/Idr.h"

#include "mlir/IR/AsmState.h"
#include "mlir/InitAllDialects.h"
#include "mlir/InitAllExtensions.h"
#include "mlir/InitAllPasses.h"
#include "mlir/Parser/Parser.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Support/FileUtilities.h"
#include "mlir/Target/LLVMIR/Dialect/Builtin/BuiltinToLLVMIRTranslation.h"
#include "mlir/Target/LLVMIR/Dialect/LLVMIR/LLVMToLLVMIRTranslation.h"
#include "mlir/Target/LLVMIR/Export.h"

#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/LegacyPassManager.h"
#include "llvm/IR/Module.h"
#include "llvm/MC/TargetRegistry.h"
#include "llvm/Passes/PassBuilder.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Support/FormatVariadic.h"
#include "llvm/Support/FileSystem.h"
#include "llvm/Support/InitLLVM.h"
#include "llvm/Support/Path.h"
#include "llvm/Support/SourceMgr.h"
#include "llvm/Support/TargetSelect.h"
#include "llvm/Support/ToolOutputFile.h"
#include "llvm/Target/TargetMachine.h"
#include "llvm/Target/TargetOptions.h"
#include "llvm/TargetParser/Host.h"
#include "llvm/TargetParser/Triple.h"

namespace cl = llvm::cl;

namespace {

cl::opt<std::string> inputPath(cl::Positional, cl::desc("<input.mlir>"), cl::Required);
cl::opt<std::string> outputPath("o", cl::desc("Output file"), cl::Required);
cl::opt<std::string> emitKind("emit", cl::desc("obj (default), llvm or mlir"),
                              cl::init("obj"));
cl::opt<std::string> dumpAfter("dump-after",
                               cl::desc("Dump the module after this step, or 'all'"),
                               cl::init(""));
cl::opt<std::string> dumpDir("dump-dir", cl::desc("Directory for --dump-after files"),
                             cl::init("."));

// Exit statuses (DRV-CC-2).
constexpr int ok = 0, failure = 1, usage = 2;

std::string stepName(llvm::StringRef step) {
  std::string name = step.split(',').first.str();
  return name;
}

bool dump(mlir::ModuleOp module, unsigned index, llvm::StringRef name) {
  if (dumpAfter.empty() || (dumpAfter != "all" && dumpAfter != name))
    return true;
  llvm::SmallString<128> path(dumpDir);
  llvm::sys::path::append(path, llvm::formatv("{0:02}-{1}.mlir", index, name).str());
  std::error_code error;
  llvm::raw_fd_ostream out(path, error);
  if (error) {
    llvm::errs() << "idris-mlir-cc: cannot write " << path << ": " << error.message() << "\n";
    return false;
  }
  module->print(out, mlir::OpPrintingFlags().enableDebugInfo());
  return true;
}

// Writes `contents` to the output path only once everything succeeded, so a
// failure never leaves a partial or stale output (DRV-CC-2).
template <typename Write> bool writeOutput(Write write) {
  std::error_code error;
  auto file = std::make_unique<llvm::ToolOutputFile>(outputPath, error, llvm::sys::fs::OF_None);
  if (error) {
    llvm::errs() << "idris-mlir-cc: cannot write " << outputPath << ": " << error.message() << "\n";
    return false;
  }
  if (!write(file->os()))
    return false;
  file->keep();
  return true;
}

int run() {
  mlir::registerAllPasses();
  idr::registerIdrPipeline();
  mlir::DialectRegistry registry;
  mlir::registerAllDialects(registry);
  mlir::registerAllExtensions(registry);
  mlir::registerBuiltinDialectTranslation(registry);
  mlir::registerLLVMDialectTranslation(registry);
  idr::registerIdr(registry);
  mlir::MLIRContext context(registry);

  llvm::SourceMgr sources;
  mlir::SourceMgrDiagnosticHandler diagnostics(sources, &context);
  mlir::OwningOpRef<mlir::ModuleOp> module =
      mlir::parseSourceFile<mlir::ModuleOp>(inputPath, sources, &context);
  if (!module)
    return failure;

  unsigned index = 0;
  for (llvm::StringRef step : idr::pipelineSteps()) {
    ++index;
    mlir::PassManager pm(&context);
    if (mlir::failed(mlir::parsePassPipeline(step, pm))) {
      llvm::errs() << "idris-mlir-cc: internal error: bad pipeline step " << step << "\n";
      return failure;
    }
    if (mlir::failed(pm.run(*module))) {
      llvm::errs() << "idris-mlir-cc: internal error: step " << index << " (" << step
                   << ") failed\n";
      return failure;
    }
    if (!dump(*module, index, stepName(step)))
      return failure;
  }
  if (emitKind == "mlir")
    return writeOutput([&](llvm::raw_ostream &os) {
             module->print(os);
             return true;
           })
               ? ok
               : failure;

  // Step 11: LLVM IR, LLVM's O2 pipeline, object code for the host.
  llvm::InitializeNativeTarget();
  llvm::InitializeNativeTargetAsmPrinter();
  llvm::Triple triple(llvm::sys::getDefaultTargetTriple());
  std::string error;
  const llvm::Target *target = llvm::TargetRegistry::lookupTarget(triple, error);
  if (!target) {
    llvm::errs() << "idris-mlir-cc: " << error << "\n";
    return failure;
  }
  llvm::TargetOptions options;
  std::unique_ptr<llvm::TargetMachine> machine(target->createTargetMachine(
      triple, "generic", "", options, llvm::Reloc::PIC_, std::nullopt,
      llvm::CodeGenOptLevel::Default));

  llvm::LLVMContext llvmContext;
  std::unique_ptr<llvm::Module> llvmModule = mlir::translateModuleToLLVMIR(*module, llvmContext);
  if (!llvmModule) {
    llvm::errs() << "idris-mlir-cc: internal error: translation to LLVM IR failed\n";
    return failure;
  }
  llvmModule->setTargetTriple(triple);
  llvmModule->setDataLayout(machine->createDataLayout());

  llvm::LoopAnalysisManager lam;
  llvm::FunctionAnalysisManager fam;
  llvm::CGSCCAnalysisManager cgam;
  llvm::ModuleAnalysisManager mam;
  llvm::PassBuilder builder(machine.get());
  builder.registerModuleAnalyses(mam);
  builder.registerCGSCCAnalyses(cgam);
  builder.registerFunctionAnalyses(fam);
  builder.registerLoopAnalyses(lam);
  builder.crossRegisterProxies(lam, fam, cgam, mam);
  llvm::ModulePassManager passes =
      builder.buildPerModuleDefaultPipeline(llvm::OptimizationLevel::O2);
  passes.run(*llvmModule, mam);

  if (emitKind == "llvm")
    return writeOutput([&](llvm::raw_ostream &os) {
             llvmModule->print(os, nullptr);
             return true;
           })
               ? ok
               : failure;
  if (emitKind != "obj") {
    llvm::errs() << "idris-mlir-cc: --emit must be obj, llvm or mlir\n";
    return usage;
  }
  return writeOutput([&](llvm::raw_ostream &os) {
           auto *pwrite = static_cast<llvm::raw_pwrite_stream *>(&os);
           llvm::legacy::PassManager codegen;
           if (machine->addPassesToEmitFile(codegen, *pwrite, nullptr,
                                            llvm::CodeGenFileType::ObjectFile)) {
             llvm::errs() << "idris-mlir-cc: the target cannot emit object files\n";
             return false;
           }
           codegen.run(*llvmModule);
           return true;
         })
             ? ok
             : failure;
}

} // namespace

int main(int argc, char **argv) {
  llvm::InitLLVM init(argc, argv);
  if (!cl::ParseCommandLineOptions(argc, argv, "idris-mlir-cc: idr to object code\n",
                                   &llvm::errs()))
    return usage;
  return run();
}
