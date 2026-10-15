// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idris-mlir's entry: the command line, the --print options and the
// compilation, on a stack of its own.

#include "idr/Driver/Main.h"

#include "idr/Driver/Artifacts.h"
#include "idr/Driver/Compile.h"
#include "idr/Driver/Options.h"
#include "idr/Driver/Report.h"
#include "idr/Driver/Runtime.h"
#include "idr/Support/Profile.h"
#include "idr/Support/Stack.h"
#include "idr/Transforms/Pipeline.h"

// The runtime's C ABI: its reserved-stack runner.
#include "idris_rt.h"

#include "mlir/Debug/CLOptionsSetup.h"
#include "mlir/IR/AsmState.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/InitAllPasses.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Support/Timing.h"

#include "llvm/ADT/STLFunctionalExtras.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Support/ErrorHandling.h"
#include "llvm/Support/InitLLVM.h"
#include "llvm/Support/raw_ostream.h"

#include <cstddef>
#include <optional>
#include <string>
#include <utility>
#include <variant>
#include <vector>

// What the stack's exhaustion handler may call: write and _exit.
#include <unistd.h>

using namespace idr::driver;

namespace {

// The compilation runs on the runtime's reserved-stack runner, on the
// tools' stack. The frontend and the link are spawned from this thread,
// which posix_spawn allows. PIN(mlir-recursion)
struct Compilation {
  llvm::function_ref<int()> body;
  int status = failure;
};

} // namespace

static void enter(void *argument) {
  // This thread's share of the trace, finished before it is joined.
  idr::profile::ThreadTrace thread;
  auto *compilation = static_cast<Compilation *>(argument);
  compilation->status = compilation->body();
}

// From the signal handler: only write and _exit.
[[noreturn]] static void compilationExhausted() {
  static constexpr char message[] =
      "idris-mlir: internal error: the compilation exhausted its stack\n";
  (void)!write(2, message, sizeof message - 1);
  _exit(failure);
}

// Runs `body` on the runtime's reserved-stack runner; its exit status.
static int runOnLargeStack(llvm::function_ref<int()> body) {
  Compilation compilation{body};
  if (idris_rt_run_on_stack(enter, &compilation, idr::support::toolStack,
                            idr::support::toolStackGuard, compilationExhausted) != 0) {
    Report() << "no stack could be reserved for the compilation";
    return failure;
  }
  return compilation.status;
}

// The compilation of the input to what -o names: its plan read from the
// command line, its directories made, and then, armed, the chain.
static int compileInput(const char *argv0) {
  if (inputPath.empty() || outputPath.empty()) {
    Report() << "give an input file and -o (see --help)";
    return usage;
  }
  Product product = objectOnly ? Product(Archive{outputPath}) : Product(Executable{outputPath});
  std::optional<Plan> plan = Plan::of(inputPath, std::move(product));
  if (!plan) {
    Report() << "-o names outputs that collide with each other or with the input";
    return usage;
  }
  bool frontendOptions = packages.getNumOccurrences() || packagePath.getNumOccurrences() ||
                         idrisPrefix.getNumOccurrences() || noPrelude.getNumOccurrences();
  if (frontendOptions && std::holds_alternative<FromModule>(plan->source)) {
    Report() << "-p, --package-path, --prefix and --no-prelude are the frontend's, for Idris "
                "source, not for a module";
    return usage;
  }
  if (!plan->makeDirectories())
    return failure;
  Artifacts artifacts(std::move(*plan));
  std::string frontendPath = frontendBeside(argv0);
  return runOnLargeStack([&] { return compile(frontendPath, artifacts); });
}

int idr::driver::main(int argc, char **argv) {
  // The folders run the runtime's big operations, whose GMP allocates where
  // a program's does, set while no other thread exists.
  idris_rt_gmp_init();
  llvm::InitLLVM init(argc, argv);
  // Every pass is registered before the options that name passes
  // (-mlir-print-ir-after and the like) are, which list the registered
  // ones.
  mlir::registerAllPasses();
  idr::registerIdrPasses();
  // MLIR's own options, as mlir-opt has them: the pass manager's (IR
  // printing, the module after each pass, statistics, crash reproducers),
  // timing, the context's, the printer's and action logging. Not a debug
  // counter: one that skips an action changes what is compiled, and the
  // compiler has one pipeline. idris-mlir-opt keeps upstream's.
  mlir::registerAsmPrinterCLOptions();
  mlir::registerMLIRContextCLOptions();
  mlir::registerPassManagerCLOptions();
  mlir::registerDefaultTimingManagerCLOptions();
  mlir::tracing::DebugConfig::registerCLOptions();
  // LLVM's -stats, which LLVM prints at exit, also prints the statistics of
  // the pipeline's passes.
  if (llvm::cl::Option *stats = llvm::cl::getRegisteredOptions().lookup("stats")) {
    stats->setDescription("Print the statistics of every pass, and LLVM's at exit");
    stats->setHiddenFlag(llvm::cl::NotHidden);
  }
  // Defaults, given first, so the command line can override them.
  // Functions and blocks not reached by fallthrough start on a 64-byte
  // line: the padding is never executed, and the hot code of a program no
  // longer moves when unrelated code changes size. A diagnostic does not
  // print the op it is about: a rejection is the user's, at their source,
  // not the compiler's IR.
  std::vector<const char *> args(argv, argv + argc);
  args.insert(args.begin() + 1, {"--align-all-functions=6", "--align-all-nofallthru-blocks=6",
                                 "--mlir-print-op-on-diagnostic=false"});
  if (!llvm::cl::ParseCommandLineOptions(static_cast<int>(args.size()), args.data(),
                                         "idris-mlir: Idris source or an idr module to an "
                                         "executable\n",
                                         &llvm::errs()))
    return usage;
  // --time-trace, when it named a file: written as this returns, by
  // whichever way out the compilation took.
  idr::profile::Trace trace("idris-mlir");
  switch (action.getValue()) {
  case Action::PrintTargetTriple:
    llvm::outs() << targetTriple << "\n";
    return ok;
  case Action::PrintTargetCpu:
    llvm::outs() << targetCpu << "\n";
    return ok;
  case Action::PrintRuntime:
    llvm::outs() << runtimePath << "\n";
    return ok;
  case Action::PrintLinkFlags:
    for (llvm::StringRef flag : linkFlags)
      llvm::outs() << flag << "\n";
    return ok;
  case Action::PrepareRuntime:
    if (!inputPath.empty()) {
      Report() << "--prepare-runtime takes no input file";
      return usage;
    }
    if (outputPath.empty()) {
      Report() << "no output file (-o)";
      return usage;
    }
    if (!makeDirectoryOf(outputPath))
      return failure;
    return runOnLargeStack(prepare);
  case Action::Compile:
    return compileInput(argv[0]);
  }
  llvm_unreachable("every action is handled");
}
