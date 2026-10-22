// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// One compilation, timed and profiled as a whole: the frontend and the link
// as child processes, the pipeline and LLVM in process, on one context
// whose diagnostic engine every step says its failures in, folded into the
// compilation's verdict, which its report and its exit status are.

#include "idr/Driver/Compile.h"

#include "idr/Driver/Artifacts.h"
#include "idr/Driver/Fold.h"
#include "idr/Driver/Options.h"
#include "idr/Driver/Report.h"
#include "idr/Driver/Tool.h"
#include "idr/Driver/Verdict.h"
#include "idr/Support/Match.h"
#include "idr/Support/Profile.h"

#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/DialectRegistry.h"
#include "mlir/IR/Location.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/Support/Timing.h"

#include "llvm/ADT/SmallString.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/Support/FileSystem.h"
#include "llvm/Support/Path.h"
#include "llvm/Support/Program.h"
#include "llvm/Support/ThreadPool.h"
#include "llvm/Support/Threading.h"

#include <iterator>
#include <optional>
#include <string>
#include <system_error>
#include <utility>
#include <vector>

using namespace idr::driver;

// Idris source to the module the plan names. The frontend
// reads no environment, so its prefix and package directories are its
// arguments. It prints no refusal: it writes each into the module it
// leaves (run reads them), so its exit status once it finished is all this
// returns. One that did not run or did not finish is the installation's,
// said in the driver's own form and recorded as such: no diagnostic of the
// compilation's says it.
static mlir::FailureOr<int> frontend(llvm::StringRef frontendPath, const FromIdris &idris,
                                     Outcome &outcome) {
  const FrontendArgs &options = idris.frontend;
  std::vector<std::string> args{frontendPath.str(), "--prefix", options.prefix};
  for (const std::string &directory : options.packagePath)
    args.insert(args.end(), {"--package-path", directory});
  for (const std::string &package : options.packages)
    args.insert(args.end(), {"-p", package});
  if (options.prelude == Prelude::NotImported)
    args.emplace_back("--no-prelude");
  args.insert(args.end(), {"-o", idris.modulePath, idris.source});
  std::vector<llvm::StringRef> argv(args.begin(), args.end());
  std::string error;
  bool notRun = false;
  int status = llvm::sys::ExecuteAndWait(frontendPath, argv, std::nullopt, {}, 0, 0, &error,
                                         &notRun);
  // A negative status is no exit of the frontend's: it was killed, or not
  // waited for.
  if (notRun || status < 0) {
    Report() << "the frontend " << frontendPath << (notRun ? " cannot run: " : " did not finish: ")
             << error;
    outcome.see(Verdict::Environment);
    return mlir::failure();
  }
  return status;
}

// The pinned clang links the objects of the program's bins, in their
// order, and the runtime's (what the program did not inline resolves
// there) into the executable, for the target the objects were compiled for.
// The last step: a link that fails is the compiler's error.
static void link(const Artifacts &artifacts, const Executable &executable,
                 llvm::StringRef runtime, mlir::MLIRContext &context) {
  std::vector<llvm::StringRef> argv{pinnedCc};
  argv.insert(argv.end(), artifacts.objects.begin(), artifacts.objects.end());
  argv.insert(argv.end(), {runtime, "-o", executable.path});
  argv.insert(argv.end(), std::begin(linkFlags), std::end(linkFlags));
  std::string error;
  bool notRun = false;
  int status = llvm::sys::ExecuteAndWait(pinnedCc, argv, std::nullopt, {}, 0, 0, &error, &notRun);
  if (notRun || status != 0)
    mlir::emitError(mlir::UnknownLoc::get(&context))
        << "linking with " << pinnedCc << " failed"
        << (notRun || status < 0 ? ": " + error : " with status " + std::to_string(status));
}

// The steps in order, until one fails, which has said why: the verdict the
// diagnostics fold into is the compilation's.
static void chain(llvm::StringRef frontendPath, const Compile &invocation, Artifacts &artifacts,
                  mlir::MLIRContext &context, Diagnostics &diagnostics,
                  llvm::ThreadPoolInterface &pool, mlir::TimingScope &rootTiming,
                  Outcome &outcome) {
  if (mlir::failed(artifacts.makeDirectories(context)))
    return;
  // What made the module: the frontend, as it finished, or the input itself,
  // which no frontend failed to make.
  mlir::FailureOr<int> made = idr::match(
      artifacts.source,
      [&](const FromIdris &idris) {
        IDR_ZONE_IN("frontend", Driver);
        mlir::TimingScope frontendTiming = rootTiming.nest("frontend");
        return frontend(frontendPath, idris, outcome);
      },
      [](const FromModule &) { return mlir::FailureOr<int>(exitStatus[Verdict::Accepted]); });
  if (mlir::failed(made) || mlir::failed(run(*made, invocation, artifacts, context,
                                             diagnostics.sources(), pool, rootTiming, outcome)))
    return;
  // An executable is linked; an archive is the bins' objects, unlinked.
  idr::match(
      artifacts.product,
      [&](const Executable &executable) {
        IDR_ZONE_IN("link", Link);
        mlir::TimingScope linkTiming = rootTiming.nest("link");
        link(artifacts, executable, invocation.runtime, context);
      },
      [](const Archive &) {});
}

std::string idr::driver::frontendBeside(const char *argv0) {
  std::string self =
      llvm::sys::fs::getMainExecutable(argv0, reinterpret_cast<void *>(&frontendBeside));
  llvm::SmallString<256> path(llvm::sys::path::parent_path(self));
  llvm::sys::path::append(path, "idris-mlir-front");
  return path.str().str();
}

int idr::driver::compile(llvm::StringRef frontendPath, Compile invocation) {
  // The compilation as one span of the trace, however it ends.
  IDR_ZONE_IN("compile", Driver);
  mlir::DefaultTimingManager timings;
  mlir::applyDefaultTimingManagerCLOptions(timings);
  mlir::TimingScope rootTiming = timings.getRootScope();
  // Declared before the context, whose diagnostics fold into it until it
  // goes.
  Outcome outcome;
  // The one pool of the compilation, which the function passes and the
  // bins' code generation run on, sized by --num-threads (every CPU by
  // default), each worker on the tools' stack as this thread is; declared
  // before the context so it outlives it, as upstream's tools declare
  // theirs. --mlir-disable-threading still wins for the passes, the context
  // then ignoring it.
  llvm::ThreadPoolStrategy strategy;
  strategy.ThreadsRequested = invocation.threads;
  llvm::StdThreadPool pool(onToolStack(strategy));
  // Every dialect a compilation meets, so a module of any other fails to
  // parse. The context runs the function groups over the functions in
  // parallel unless --mlir-disable-threading; two compiles of one module
  // are the same bytes either way, since no pass keeps state a worker
  // thread shares. Created disabled so the pool can be set (setThreadPool
  // requires it and enables threading itself); --mlir-disable-threading
  // keeps it disabled, as upstream's tools arrange the same pair.
  mlir::DialectRegistry registry;
  registerCompiler(registry);
  mlir::MLIRContext context(registry, mlir::MLIRContext::Threading::DISABLED);
  context.setThreadPool(pool);
  Diagnostics diagnostics(context, outcome);
  Artifacts artifacts(std::move(invocation.plan));
  chain(frontendPath, invocation, artifacts, context, diagnostics, pool, rootTiming, outcome);
  // Whatever the verdict: the report says why a compilation failed. One that
  // cannot be written is the compiler's error, which fails the compilation,
  // so it keeps nothing.
  if (artifacts.report)
    if (std::error_code error = writeReport(*artifacts.report, outcome))
      cannotWrite(context, *artifacts.report, error);
  if (outcome.verdict() == Verdict::Accepted)
    artifacts.keep();
  return exitStatus[outcome.verdict()];
}
