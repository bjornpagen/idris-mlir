// idris-mlir's entry: the command line, the --print options and the
// compilation, on a stack of its own.

#include "idr/Driver/Main.h"

#include "idr/Driver/Artifacts.h"
#include "idr/Driver/Compile.h"
#include "idr/Driver/Options.h"
#include "idr/Driver/Report.h"
#include "idr/Driver/Runtime.h"
#include "idr/Transforms/Pipeline.h"

// The runtime's C ABI: its reserved-stack runner.
#include "idris_rt.h"

#include "mlir/Debug/CLOptionsSetup.h"
#include "mlir/Debug/Counter.h"
#include "mlir/IR/AsmState.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/InitAllPasses.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Support/Timing.h"

#include "llvm/ADT/STLFunctionalExtras.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Support/InitLLVM.h"
#include "llvm/Support/raw_ostream.h"

#include <cstddef>
#include <string>
#include <vector>

// What the stack's exhaustion handler may call: write and _exit.
#include <unistd.h>

using namespace idr::driver;

namespace {

// The compilation runs on the runtime's reserved-stack runner, on a stack
// committed as it is touched: MLIR's parser, printer and walks recurse over
// nested constants. The stack is 2^40 bytes, more than the memory of a
// machine that compiles, so memory runs out first; no more, since reserving
// costs time in proportion to the size, at the start and at the exit. The
// frontend and the link are spawned from this thread, which posix_spawn
// allows. PIN(mlir-recursion)
struct Compilation {
  llvm::function_ref<int()> body;
  int status = failure;
};

} // namespace

static void enter(void *argument) {
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
  if (idris_rt_run_on_stack(enter, &compilation, size_t{1} << 40, size_t{1} << 20,
                            compilationExhausted) != 0) {
    Report() << "no stack could be reserved for the compilation";
    return failure;
  }
  return compilation.status;
}

int idr::driver::main(int argc, char **argv) {
  llvm::InitLLVM init(argc, argv);
  // Every pass is registered before the options that name passes
  // (-mlir-print-ir-after and the like) are, which list the registered
  // ones.
  mlir::registerAllPasses();
  idr::registerIdrPasses();
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
  if (printTargetTriple) {
    llvm::outs() << targetTriple << "\n";
    return ok;
  }
  if (printTargetCpu) {
    llvm::outs() << targetCpu << "\n";
    return ok;
  }
  if (printRuntime) {
    llvm::outs() << runtimePath << "\n";
    return ok;
  }
  if (printLinkFlags) {
    for (llvm::StringRef flag : linkFlags)
      llvm::outs() << flag << "\n";
    return ok;
  }
  if (prepareRuntime) {
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
  }
  if (inputPath.empty() || outputPath.empty()) {
    Report() << "give an input file and -o (see --help)";
    return usage;
  }
  Input kind = inputKind(inputPath);
  bool frontendOptions = packages.getNumOccurrences() || packagePath.getNumOccurrences() ||
                         idrisPrefix.getNumOccurrences() || noPrelude.getNumOccurrences() ||
                         breakShape.getNumOccurrences();
  if (kind == Input::Module && frontendOptions) {
    Report() << "-p, --package-path, --prefix, --no-prelude and --break-shape are the "
                "frontend's, for Idris source, not for a module";
    return usage;
  }
  // Nothing is removed before the artifacts are armed: a usage error leaves
  // every file as it was.
  Artifacts artifacts(inputPath, kind, outputPath, objectOnly);
  if (!artifacts.distinctFromInput(inputPath)) {
    Report() << "-o names outputs that collide with each other or with the input";
    return usage;
  }
  if (!artifacts.makeDirectories())
    return failure;
  artifacts.arm();
  std::string frontendPath = frontendBeside(argv[0]);
  return runOnLargeStack([&] { return compile(frontendPath, kind, artifacts); });
}
