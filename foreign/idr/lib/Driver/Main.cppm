// idr.driver:main: idris-mlir-cc's entry, which the tool's `main` calls:
// MLIR's and LLVM's options with its own, the --print options, which answer
// what the build decided, and the compilation.
module;
// The target entry's link flags, an X-macro.
#include "idr/TargetEntry.h"

export module idr.driver:main;

import idr.mlir;

import :options;
import :runonlargestack;

export namespace idr::driver {

// Parses the command line, answers a --print option, or compiles; the exit
// status.
int main(int argc, char **argv) {
  llvm::InitLLVM init(argc, argv);
  // MLIR's own options, as mlir-opt has them: the pass manager's (IR
  // printing, statistics, crash reproducers), timing, the context's, the
  // printer's, action logging and debug counters.
  mlir::registerAsmPrinterCLOptions();
  mlir::registerMLIRContextCLOptions();
  mlir::registerPassManagerCLOptions();
  mlir::registerDefaultTimingManagerCLOptions();
  mlir::tracing::DebugConfig::registerCLOptions();
  mlir::tracing::DebugCounter::registerCLOptions();
  // LLVM's -stats, which LLVM prints at exit, also prints the statistics of
  // each step's passes.
  if (llvm::cl::Option *stats = llvm::cl::getRegisteredOptions().lookup("stats")) {
    stats->setDescription("Print the statistics of every pass, and LLVM's at exit");
    stats->setHiddenFlag(llvm::cl::NotHidden);
  }
  // Functions and blocks not reached by fallthrough start on a
  // 64-byte line. The padding is never executed, and the hot code of a
  // program no longer moves when unrelated code changes size. Given first,
  // so the command line can override them.
  std::vector<const char *> args(argv, argv + argc);
  args.insert(args.begin() + 1,
              {"--align-all-functions=6", "--align-all-nofallthru-blocks=6"});
  if (!llvm::cl::ParseCommandLineOptions(static_cast<int>(args.size()), args.data(),
                                   "idris-mlir-cc: idr to object code\n", &llvm::errs()))
    return usage;
  if (printTargetTriple) {
    llvm::outs() << targetTriple << "\n";
    return ok;
  }
  if (printTargetCpu) {
    llvm::outs() << (targetCpu == "native" ? llvm::sys::getHostCPUName().str() : targetCpu)
                 << "\n";
    return ok;
  }
  if (printRuntime) {
    llvm::outs() << runtimePath << "\n";
    return ok;
  }
  if (printLinkFlags) {
#define IDR_LINK_FLAG(flag) llvm::outs() << flag << "\n";
    IDRIS_MLIR_LINK_FLAGS(IDR_LINK_FLAG)
#undef IDR_LINK_FLAG
    return ok;
  }
  if (inputPath.empty() != prepareRuntime) {
    llvm::errs() << (prepareRuntime ? "idris-mlir-cc: --prepare-runtime takes no input file\n"
                                    : "idris-mlir-cc: no input file (see --help)\n");
    return usage;
  }
  return runOnLargeStack();
}

} // namespace idr::driver
