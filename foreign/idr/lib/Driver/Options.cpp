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
cl::opt<std::string> outputPath("o", cl::desc("Output: the executable, or with -c the object"),
                                cl::init(""));
// What the compilation makes: the executable, linked by the pinned clang
// with the runtime, or with -c only the object it links.
cl::opt<bool> objectOnly("c", cl::desc("Compile to an object (-o), without linking"),
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
// A test hook (tests/registry): the frontend breaks the shape of the
// registry's entry of this key, which the validation must then reject.
cl::opt<std::string> breakShape("break-shape", cl::Hidden,
                                cl::desc("Break the shape of the registry's entry of this key"),
                                cl::init(""));
cl::list<std::string> without(
    "without", cl::CommaSeparated,
    cl::desc("Leave out these passes of the pipeline (an idr-* pass other than idr-lower) or "
             "these options of idr-rc and idr-demand (reuse, sink, in-place), to measure what "
             "each one is worth"));
// The promise idr-demand checks: a program that breaks it is rejected.
// Without it, idr-demand checks nothing.
cl::opt<bool> demandInPlace(
    "demand-in-place",
    cl::desc("Reject a program unless every call passes a parameter of quantity 1 that its "
             "function rebuilds in place exclusive"),
    cl::init(false));
// Which actions -log-actions-to logs: otherwise every one, each pass
// execution with the whole module.
cl::list<std::string> logActionsTags(
    "log-actions-tags",
    cl::desc("With -log-actions-to, log only the actions of these tags, e.g. idr-specialize-clone"),
    cl::CommaSeparated);
// The module after each pass of the pipeline, `<NN>-<pass>.mlir` in this
// directory.
cl::opt<std::string> dumpDir("dump-dir",
                             cl::desc("Write the module after each pass of the pipeline into "
                                      "this directory, as <NN>-<pass>.mlir"),
                             cl::init(""));
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
// the target entry's container says (CMakeLists.txt): in a section of its
// object that every link leaves out, or, with no section, in a file of its
// own beside the object, which no link names.
cl::opt<std::string> runtimeBitcodeSection(
    "runtime-bitcode-section",
    cl::desc("The section of the prepared runtime's object that holds its bitcode (by default "
             "the target entry's), or '' for a file beside the object, named as it is with .bc"),
    cl::init(IDRIS_MLIR_RUNTIME_BITCODE_SECTION));
cl::opt<bool> printRuntime("print-runtime",
                           cl::desc("Print the path of the runtime --runtime names, which "
                                    "every executable links, and exit"),
                           cl::init(false));
// The runtime is the same for every program, so it is optimized and
// compiled once, at build time, and each compilation links the result: what
// it then optimizes again is the program, and the runtime code it inlines.
cl::opt<bool> prepareRuntime("prepare-runtime",
                             cl::desc("Optimize the runtime archive --runtime names once, for "
                                      "the target's CPU, into the object -o: native code for "
                                      "the link line with its bitcode for inlining, which "
                                      "every compilation then links (no input file)"),
                             cl::init(false));
cl::opt<bool> printTargetTriple("print-target-triple",
                                cl::desc("Print the target triple executables are linked for, "
                                         "and exit"),
                                cl::init(false));
// What links a program for the target entry, after its object, the runtime
// and -o, one argument of the pinned C compiler per line: --target with the
// triple, then the entry's executable and program link flags and GMP. The
// link and the tests that link by hand use these.
cl::opt<bool> printLinkFlags("print-link-flags",
                             cl::desc("Print the arguments that link a program for the target, "
                                      "after its object, the runtime and -o, one per line, and "
                                      "exit"),
                             cl::init(false));
// What other compilers need to compile for the same machine, bench/run.sh's
// C versions among them.
cl::opt<bool> printTargetCpu("print-target-cpu",
                             cl::desc("Print the CPU code is compiled for, and exit"),
                             cl::init(false));
// The size of the MLIR thread pool a compilation runs its function
// passes on. Output bytes do not depend on it; it exists so a compile
// leaves the machine usable, and so a caller running compilations in
// parallel can divide its own budget among them.
cl::opt<unsigned> numThreads(
    "num-threads",
    cl::desc("Threads for the pipeline's parallel function passes (default: every CPU); "
             "output bytes do not depend on it"),
    cl::init(0));

unsigned threadBudget() {
  if (numThreads > 0)
    return numThreads;
  return std::max(1u, llvm::hardware_concurrency().compute_thread_count());
}

} // namespace idr::driver
