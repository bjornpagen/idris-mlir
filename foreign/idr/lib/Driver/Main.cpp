// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idris-mlir's entry: the command line, read once into the invocation, and
// then what it asks, on the tools' stack.

#include "idr/Driver/Main.h"

#include "idr/Driver/Compile.h"
#include "idr/Driver/Options.h"
#include "idr/Driver/Report.h"
#include "idr/Driver/Runtime.h"
#include "idr/Driver/Tool.h"
#include "idr/Driver/Verdict.h"
#include "idr/Support/Match.h"
#include "idr/Support/Profile.h"
#include "idr/Target/Target.h"

#include "mlir/Debug/CLOptionsSetup.h"
#include "mlir/Debug/Counter.h"
#include "mlir/IR/AsmState.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Support/Timing.h"

#include "llvm/ADT/StringRef.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Support/Error.h"
#include "llvm/Support/ErrorHandling.h"
#include "llvm/Support/InitLLVM.h"
#include "llvm/Support/raw_ostream.h"

#include <utility>
#include <vector>

using namespace idr::driver;

// The answer to a question about what the build decided, on standard
// output.
static void answer(Question question) {
  switch (question) {
  case Question::Runtime:
    llvm::outs() << preparedRuntime << "\n";
    return;
  case Question::TargetTriple:
    llvm::outs() << idr::target::triple << "\n";
    return;
  case Question::LinkFlags:
    for (llvm::StringRef flag : linkFlags)
      llvm::outs() << flag << "\n";
    return;
  case Question::CpuFlags:
    for (llvm::StringRef flag : programCpuFlags)
      llvm::outs() << flag << "\n";
    return;
  }
  llvm_unreachable("every question has its answer");
}

int idr::driver::main(int argc, char **argv) {
  llvm::InitLLVM init(argc, argv);
  // Every pass the compiler runs is registered before the options that
  // name passes (-mlir-print-ir-after and the like) are, which list the
  // registered ones; a pass the compiler does not run is no such option's.
  registerCompilerPasses();
  // MLIR's own options, as mlir-opt has them: the pass manager's (IR
  // printing, the module after each pass, statistics, crash reproducers),
  // timing, the context's, the printer's, action logging, and the debug
  // counter, with which a test skips a drawn set of the optimizations'
  // actions: a transform skipped leaves the program accepted alike and
  // ending alike, since acceptance is the program's, never the optimizer's.
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
                                         "Idris source or an idr module to an executable\n",
                                         &llvm::errs()))
    return usage;
  llvm::Expected<Invocation> invocation = readInvocation();
  if (!invocation) {
    Report() << llvm::toString(invocation.takeError());
    return usage;
  }
  // --time-trace, when it named a file: written as this returns, by
  // whichever way out the invocation took.
  idr::profile::Trace trace(toolName);
  return runTool([&] {
    return idr::match(
        *invocation,
        [&](Compile &compiling) { return compile(frontendBeside(argv[0]), std::move(compiling)); },
        [](const Prepare &preparing) { return prepare(preparing); },
        [](const Print &asked) {
          answer(asked.question);
          return int{exitStatus[Verdict::Accepted]};
        });
  });
}
