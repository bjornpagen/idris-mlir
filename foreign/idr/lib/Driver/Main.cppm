// idr.driver:main: idris-mlir's entry, which the tool's `main` calls:
// MLIR's and LLVM's options with its own, the --print options, which answer
// what the build decided, and the compilation.
export module idr.driver:main;

import idr.mlir;

import :artifacts;
import :compile;
import :frontend;
import :link;
import :options;
import :report;
import :run;
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
    return runOnLargeStack([] {
      mlir::DefaultTimingManager timings;
      mlir::applyDefaultTimingManagerCLOptions(timings);
      mlir::TimingScope rootTiming = timings.getRootScope();
      return run("", outputPath, rootTiming);
    });
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
  artifacts.arm();
  std::string frontendPath = frontendBeside(argv[0]);
  return runOnLargeStack([&] { return compile(frontendPath, kind, artifacts); });
}

} // namespace idr::driver
