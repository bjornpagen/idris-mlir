// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idris-mlir's options, defined in the order --help lists them, and the
// one reading of them into the invocation. They are the command line's:
// written once by ParseCommandLineOptions, read once here, and by nothing
// else.

#include "idr/Driver/Options.h"

#include "idr/Driver/Artifacts.h"

#include "mlir/Debug/CLOptionsSetup.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/Pass/PassManager.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/ADT/Twine.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Support/Error.h"
#include "llvm/Support/ErrorHandling.h"
#include "llvm/Support/FileSystem.h"
#include "llvm/Support/Threading.h"
#include "llvm/Support/ToolOutputFile.h"

#include <algorithm>
#include <memory>
#include <optional>
#include <string>
#include <system_error>
#include <utility>
#include <variant>

namespace cl = llvm::cl;

using namespace idr::driver;

namespace {

// Required unless another action is asked for. A module is MLIR's, text or
// bytecode; any other input is Idris source, the frontend's to read or
// refuse.
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
// The frontend's module kept where a test asks, whatever the verdict, as
// the report is: a refused program's module compiled again.
cl::opt<std::string> emittedPath("emitted",
                                 cl::desc("Keep the module the frontend emits at this path, "
                                          "whatever the verdict"),
                                 cl::init(""));
// Which actions -log-actions-to logs: otherwise every one, each pass
// execution with the whole module. The help names no tag: the passes'
// tags are the specification's, which idris-mlir-opt prints.
cl::list<std::string> logActionsTags(
    "log-actions-tags",
    cl::desc("With -log-actions-to, log only the actions of these tags, as "
             "idris-mlir-opt --idr-action-tags prints them"),
    cl::CommaSeparated);
// The runtime a compilation reads and links, and the archive
// --prepare-runtime reads: by default the object the build prepared from
// the runtime's archive, whose bitcode joins the program, and which every
// executable's link line names (--print-runtime).
cl::opt<std::string> runtimePath("runtime",
                                 cl::desc("The runtime whose bitcode joins the program, and "
                                          "which executables link: what --prepare-runtime "
                                          "wrote, or the archive it reads"),
                                 cl::init(preparedRuntime.str()));

// What an invocation does: compile, by default, or the action of the one
// flag the command line names, the last it gives. The runtime is the same
// for every program, so it is optimized and compiled once, at build time,
// and each compilation links the result: what it then optimizes again is
// the program, and the runtime code it inlines. What links a program for
// the target entry, after its objects, the runtime and -o, is one argument
// of the pinned C compiler per line: --target with the triple, then the
// entry's executable and program link flags and GMP; the link and the tests
// that link by hand use these. The CPU's flags are what the pinned C
// compiler needs to compile for the same machine, bench/run.sh's C versions
// among them.
enum class Action {
  Compile,
  PrepareRuntime,
  PrintRuntime,
  PrintTargetTriple,
  PrintLinkFlags,
  PrintCpuFlags,
};
cl::opt<Action> action(
    cl::values(clEnumValN(Action::PrintRuntime, "print-runtime",
                          "Print the path of the runtime the build prepared, which every "
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
               clEnumValN(Action::PrintCpuFlags, "print-cpu-flags",
                          "Print the C compiler's flags for the CPU code is compiled for, one "
                          "per line, and exit")),
    cl::desc("Instead of compiling the input"), cl::init(Action::Compile));

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
// The default is maximal; a caller that wants headroom (our build and test
// scripts do, through IDRIS_MLIR_NCPU) says so with the flag.
cl::opt<unsigned, false, ThreadCount> numThreads(
    "num-threads",
    cl::desc("Threads for the pipeline's parallel function passes and the bins' code "
             "generation, one at least (default: every CPU); output bytes do not depend on it"));

// A test's check of every pass as it runs (idr/Transforms/Contracts.h), as
// idris-mlir-opt has it: it fails the compilation naming the pass that
// broke a contract, and is never a choice of how a program is compiled.
cl::opt<bool> contracts("idr-contracts",
                        cl::desc("Check after every pass on the module or the program the "
                                 "relations it must keep, and fail naming the pass that broke "
                                 "one"),
                        cl::init(false));

// A test's statement of what holds at a stage of the pipeline
// (idr/Transforms/Expect.h), checked in the compilation itself after every
// pass that leaves the program at the stage, as idris-mlir-opt has it.
cl::list<std::string> expectAt(
    "idr-expect-at",
    cl::desc("Check properties of a stage after every pass that leaves the program at it: "
             "<stage>:<property>,..."));

// Every option of the driver's own, each read by the actions that name it
// below; MLIR's and LLVM's are theirs. (A cl::list's & is its vector's.)
const cl::Option *const driverOptions[] = {
    std::addressof(inputPath),      std::addressof(outputPath),  std::addressof(reportPath),
    std::addressof(objectOnly),     std::addressof(packages),    std::addressof(packagePath),
    std::addressof(idrisPrefix),    std::addressof(noPrelude),   std::addressof(emittedPath),
    std::addressof(logActionsTags), std::addressof(runtimePath), std::addressof(numThreads),
    std::addressof(contracts),      std::addressof(expectAt),
};

// The frontend's options, which only Idris source reads.
const cl::Option *const frontendOnly[] = {std::addressof(packages), std::addressof(packagePath),
                                          std::addressof(idrisPrefix), std::addressof(noPrelude),
                                          std::addressof(emittedPath)};

bool given(const cl::Option *option) { return option->getNumOccurrences() != 0; }

// An option as the command line spells it, or the input.
std::string spelled(const cl::Option &option) {
  if (option.isPositional())
    return "input file";
  return (llvm::Twine(option.ArgStr.size() == 1 ? "-" : "--") + option.ArgStr).str();
}

// `doing` reads `reads` and no other option of the driver's: the first
// other one given is the usage error.
llvm::Error readsOnly(llvm::StringRef doing, llvm::ArrayRef<const cl::Option *> reads) {
  for (const cl::Option *option : driverOptions)
    if (given(option) && !llvm::is_contained(reads, option))
      return llvm::createStringError(doing + " takes no " + spelled(*option));
  return llvm::Error::success();
}

// What MLIR's own options ask that only the command line decides, checked
// before anything runs, so that it is a usage error that arms nothing: the
// pass manager's options against threading, on a manager of a scratch
// context, whose threading is the compilation's (--mlir-disable-threading);
// and the files MLIR's action handler writes, which it would report it
// cannot open and then run without. A file is opened as the handler opens
// it, and not kept.
llvm::Error checkMlirOptions() {
  mlir::MLIRContext scratch;
  std::string said;
  mlir::ScopedDiagnosticHandler capture(&scratch, [&](mlir::Diagnostic &diagnostic) {
    said = diagnostic.str();
    return mlir::success();
  });
  mlir::PassManager manager(&scratch);
  if (mlir::failed(mlir::applyPassManagerCLOptions(manager)))
    return llvm::createStringError(llvm::StringRef(said).rtrim());
  mlir::tracing::DebugConfig config = mlir::tracing::DebugConfig::createFromCLOptions();
  const std::pair<llvm::StringLiteral, llvm::StringRef> written[] = {
      {"--log-actions-to", config.getLogActionsTo()},
      {"--profile-actions-to", config.getProfileActionsTo()}};
  for (auto [flag, path] : written) {
    if (path.empty())
      continue;
    std::error_code error;
    llvm::ToolOutputFile file(path, error, llvm::sys::fs::OF_None);
    if (error)
      return llvm::createStringError("cannot write " + path + ", which " + flag +
                                     " names: " + error.message());
  }
  return llvm::Error::success();
}

// The stage requests --idr-expect-at writes, read once here, before
// anything runs, on a scratch context whose diagnostic is the usage error.
llvm::Expected<llvm::SmallVector<idr::expect::StageRequest>> stageRequests() {
  mlir::MLIRContext scratch;
  std::string said;
  mlir::ScopedDiagnosticHandler capture(&scratch, [&](mlir::Diagnostic &diagnostic) {
    said = diagnostic.str();
    return mlir::success();
  });
  llvm::SmallVector<idr::expect::StageRequest> requests;
  for (const std::string &written : expectAt) {
    mlir::FailureOr<llvm::SmallVector<idr::expect::StageRequest>> read =
        idr::expect::parseStageRequests(&scratch, written);
    if (mlir::failed(read))
      return llvm::createStringError(llvm::StringRef(said).rtrim());
    llvm::append_range(requests, *read);
  }
  return requests;
}

std::optional<std::string> givenPath(const cl::opt<std::string> &path) {
  if (path.empty())
    return std::nullopt;
  return path.getValue();
}

llvm::Expected<Invocation> compileInvocation() {
  if (inputPath.empty() || outputPath.empty())
    return llvm::createStringError("give an input file and -o (see --help)");
  Product product = objectOnly ? Product(Archive{outputPath}) : Product(Executable{outputPath});
  FrontendArgs frontend{idrisPrefix, packagePath, packages, noPrelude};
  std::optional<Plan> plan = Plan::of(inputPath, std::move(product), givenPath(reportPath),
                                      givenPath(emittedPath), std::move(frontend));
  if (!plan)
    return llvm::createStringError("-o, --report and --emitted name outputs that collide with "
                                   "each other or with the input");
  // A module has no frontend to give them to (FromModule holds none).
  if (std::holds_alternative<FromModule>(plan->source) && llvm::any_of(frontendOnly, given))
    return llvm::createStringError("-p, --package-path, --prefix, --no-prelude and --emitted "
                                   "are the frontend's, for Idris source, not for a module");
  if (llvm::Error error = checkMlirOptions())
    return std::move(error);
  llvm::Expected<llvm::SmallVector<idr::expect::StageRequest>> stages = stageRequests();
  if (!stages)
    return stages.takeError();
  unsigned threads = given(std::addressof(numThreads))
                         ? numThreads.getValue()
                         : std::max(1u, llvm::hardware_concurrency().compute_thread_count());
  return Compile{std::move(*plan),
                 runtimePath,
                 threads,
                 logActionsTags,
                 contracts ? PassChecks::Contracts : PassChecks::Verifier,
                 std::move(*stages)};
}

} // namespace

llvm::Expected<Invocation> idr::driver::readInvocation() {
  // Compiling reads every option of the driver's; each other action reads
  // its own, and a print none.
  auto print = [](Question question) -> llvm::Expected<Invocation> {
    if (llvm::Error error = readsOnly("a --print option", {}))
      return std::move(error);
    return Print{question};
  };
  switch (action.getValue()) {
  case Action::Compile:
    return compileInvocation();
  case Action::PrepareRuntime:
    if (llvm::Error error = readsOnly("--prepare-runtime", {std::addressof(outputPath),
                                                            std::addressof(runtimePath)}))
      return std::move(error);
    if (outputPath.empty())
      return llvm::createStringError("no output file (-o)");
    return Prepare{outputPath, runtimePath};
  case Action::PrintRuntime:
    return print(Question::Runtime);
  case Action::PrintTargetTriple:
    return print(Question::TargetTriple);
  case Action::PrintLinkFlags:
    return print(Question::LinkFlags);
  case Action::PrintCpuFlags:
    return print(Question::CpuFlags);
  }
  llvm_unreachable("every action is read");
}
