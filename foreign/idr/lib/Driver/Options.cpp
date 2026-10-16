// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idris-mlir's options, defined in the order --help lists them. They are the
// command line's: written once by ParseCommandLineOptions, before anything
// reads them.

#include "idr/Driver/Options.h"

#include "llvm/Support/CommandLine.h"
#include "llvm/Support/Threading.h"

#include <algorithm>
#include <string>

namespace cl = llvm::cl;

namespace idr::driver {

// Required unless a --print option asks only what the build decided. A
// module is MLIR's, text or bytecode; any other input is Idris source, the
// frontend's to read or refuse.
cl::opt<std::string> inputPath(cl::Positional,
                               cl::desc("<input: Idris source, or a module (.mlir, .mlirbc)>"));
cl::opt<std::string> outputPath("o",
                                cl::desc("Output: the executable, or with -c the archive of its "
                                         "objects"),
                                cl::init(""));
// An output of a compilation, and the one that outlives a failure: it says
// why the compilation failed.
cl::opt<std::string> reportPath("report",
                                cl::desc("Write the compilation's verdict, diagnostics and pass "
                                         "statistics to this file, whatever the verdict"),
                                cl::init(""));
// What the compilation makes: the executable, linked by the pinned clang
// with the runtime, or with -c only the objects it links, as one archive.
cl::opt<bool> objectOnly("c",
                         cl::desc("Compile to the archive of the program's objects (-o), "
                                  "without linking"),
                         cl::init(false));
// The frontend's options, for Idris source: where Idris finds packages,
// which it loads, whether the Prelude is imported implicitly. The frontend
// reads no environment, so these are the whole of its search path.
cl::list<std::string> packages("p", cl::desc("Load the Idris package of this name"));
cl::list<std::string> packagePath("package-path",
                                  cl::desc("Look for Idris packages in this directory too"));
cl::opt<std::string> idrisPrefix("prefix",
                                 cl::desc("The Idris prefix whose packages the frontend reads"),
                                 cl::init(IDRIS_MLIR_IDRIS_PREFIX));
cl::opt<bool> noPrelude("no-prelude", cl::desc("Do not import the Prelude implicitly"),
                        cl::init(false));
// Which actions -log-actions-to logs: otherwise every one, each pass
// execution with the whole module.
cl::list<std::string> logActionsTags(
    "log-actions-tags",
    cl::desc("With -log-actions-to, log only the actions of these tags, e.g. idr-specialize-clone"),
    cl::CommaSeparated);
// The runtime, recorded at build time: the object --prepare-runtime wrote
// from the runtime's archive, or that archive itself. Its bitcode joins the
// program's module, and the same file is on every executable's link line
// (--print-runtime).
cl::opt<std::string> runtimePath("runtime",
                                 cl::desc("The runtime whose bitcode joins the program, and "
                                          "which executables link: what --prepare-runtime "
                                          "wrote, or the archive it reads"),
                                 cl::init(IDRIS_MLIR_RUNTIME));
// Where the prepared runtime keeps the bitcode that joins every program, as
// the target entry's container says (CMakeLists.txt). Read once, by
// runtimeBitcodeHome.
cl::opt<std::string> runtimeBitcodeSection(
    "runtime-bitcode-section",
    cl::desc("The section of the prepared runtime's object that holds its bitcode (by default "
             "the target entry's), or '' for a file beside the object, named as it is with .bc"),
    cl::init(IDRIS_MLIR_RUNTIME_BITCODE_SECTION));
// The other actions, each its flag. The runtime is the same for every
// program, so it is optimized and compiled once, at build time, and each
// compilation links the result: what it then optimizes again is the
// program, and the runtime code it inlines. What links a program for the
// target entry, after its objects, the runtime and -o, is one argument of
// the pinned C compiler per line: --target with the triple, then the
// entry's executable and program link flags and GMP; the link and the tests
// that link by hand use these. The CPU is what other compilers need to
// compile for the same machine, bench/run.sh's C versions among them.
cl::opt<Action> action(
    cl::values(clEnumValN(Action::PrintRuntime, "print-runtime",
                          "Print the path of the runtime --runtime names, which every "
                          "executable links, and exit"),
               clEnumValN(Action::PrepareRuntime, "prepare-runtime",
                          "Optimize the runtime archive --runtime names once, for the target's "
                          "CPU, into the object -o: native code for the link line with its "
                          "bitcode for inlining, which every compilation then links (no input "
                          "file)"),
               clEnumValN(Action::PrintTargetTriple, "print-target-triple",
                          "Print the target triple executables are linked for, and exit"),
               clEnumValN(Action::PrintLinkFlags, "print-link-flags",
                          "Print the arguments that link a program for the target, after its "
                          "objects, the runtime and -o, one per line, and exit"),
               clEnumValN(Action::PrintTargetCpu, "print-target-cpu",
                          "Print the CPU code is compiled for, and exit")),
    cl::desc("Instead of compiling the input"), cl::init(Action::Compile));

namespace {

// A count of threads, which is at least one: no thread runs no compilation.
struct ThreadCount : cl::parser<unsigned> {
  using cl::parser<unsigned>::parser;

  bool parse(cl::Option &option, llvm::StringRef name, llvm::StringRef arg, unsigned &value) {
    if (cl::parser<unsigned>::parse(option, name, arg, value))
      return true;
    if (value != 0)
      return false;
    return option.error("a compilation runs on one thread at least, not 0");
  }
};

// The size of the thread pool a compilation runs its function passes and
// its bins' code generation on, when given. Output bytes do not depend on
// it; it exists so a compile leaves the machine usable, and so a caller
// running compilations in parallel can divide its own budget among them.
cl::opt<unsigned, false, ThreadCount> numThreads(
    "num-threads",
    cl::desc("Threads for the pipeline's parallel function passes and the bins' code "
             "generation, one at least (default: every CPU); output bytes do not depend on it"));

} // namespace

BitcodeHome runtimeBitcodeHome() {
  if (runtimeBitcodeSection.empty())
    return BesideObject{};
  return InSection{runtimeBitcodeSection};
}

unsigned threadBudget() {
  if (numThreads.getNumOccurrences() != 0)
    return numThreads;
  return std::max(1u, llvm::hardware_concurrency().compute_thread_count());
}

} // namespace idr::driver
