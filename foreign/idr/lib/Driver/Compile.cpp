// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// One compilation, timed and profiled as a whole: the frontend and the link
// as child processes, the pipeline and LLVM in process, each step folded
// into the compilation's verdict, which its report and its exit status
// are.

#include "idr/Driver/Compile.h"

#include "idr/Driver/Artifacts.h"
#include "idr/Driver/Options.h"
#include "idr/Driver/Report.h"
#include "idr/Driver/Verdict.h"
#include "idr/Support/Profile.h"

#include "mlir/Support/Timing.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallString.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/Support/FileSystem.h"
#include "llvm/Support/Path.h"
#include "llvm/Support/Program.h"
#include "llvm/Support/ToolOutputFile.h"

#include <iterator>
#include <optional>
#include <string>
#include <system_error>
#include <variant>
#include <vector>

using namespace idr::driver;

// Idris source to the Core and the module the plan names. The frontend
// reads no environment, so its prefix and package directories are its
// arguments. It prints Idris's errors and its own rejections as Idris
// prints them, and exits with this tool's statuses, read back here as the
// verdict that gives each: 3 is the program's, refused; anything else but
// 0, or a frontend that did not run or did not finish, is the compiler's.
static Verdict frontend(llvm::StringRef frontendPath, const FromIdris &idris) {
  std::vector<std::string> args{frontendPath.str(), "--prefix", idrisPrefix.getValue()};
  for (const std::string &directory : packagePath)
    args.insert(args.end(), {"--package-path", directory});
  for (const std::string &package : packages)
    args.insert(args.end(), {"-p", package});
  if (noPrelude)
    args.emplace_back("--no-prelude");
  args.insert(args.end(), {"--core", idris.corePath, "-o", idris.modulePath, idris.source});
  std::vector<llvm::StringRef> argv(args.begin(), args.end());
  std::string error;
  bool notRun = false;
  int status = llvm::sys::ExecuteAndWait(frontendPath, argv, std::nullopt, {}, 0, 0, &error,
                                         &notRun);
  if (notRun) {
    Report() << "cannot run " << frontendPath << ": " << error;
    return Verdict::Internal;
  }
  if (status == ok)
    return Verdict::Accepted;
  if (status == rejected)
    return Verdict::Refused;
  if (status < 0)
    Report() << "internal error: " << frontendPath << " did not finish: " << error;
  else
    Report() << "internal error: " << frontendPath << " exited with status " << status;
  return Verdict::Internal;
}

// The pinned clang links the objects of the program's bins, in their
// order, and the runtime's (what the program did not inline resolves
// there) into the executable, for the target the objects were compiled for.
// A link that fails is the compiler's.
static Verdict link(const Artifacts &artifacts, const Executable &executable) {
  std::vector<llvm::StringRef> argv{pinnedCc};
  argv.insert(argv.end(), artifacts.objects.begin(), artifacts.objects.end());
  argv.insert(argv.end(), {runtimePath.getValue(), "-o", executable.path});
  argv.insert(argv.end(), std::begin(linkFlags), std::end(linkFlags));
  std::string error;
  bool notRun = false;
  int status = llvm::sys::ExecuteAndWait(pinnedCc, argv, std::nullopt, {}, 0, 0, &error, &notRun);
  if (notRun || status != 0) {
    Report() << "internal error: linking with " << pinnedCc << " failed"
             << (notRun || status < 0 ? ": " + error : " with status " + std::to_string(status));
    return Verdict::Internal;
  }
  return Verdict::Accepted;
}

// The steps in order, each folded into `outcome`, until one stops the
// compilation; the exit status of the verdict, or of a usage error, which
// is the command line's and has no verdict of its own.
static int chain(llvm::StringRef frontendPath, Artifacts &artifacts, Outcome &outcome,
                 mlir::TimingScope &rootTiming) {
  outcome.see(std::visit(llvm::makeVisitor(
                             [&](const FromIdris &idris) {
                               IDR_ZONE_IN("frontend", Driver);
                               mlir::TimingScope frontendTiming = rootTiming.nest("frontend");
                               return frontend(frontendPath, idris);
                             },
                             [](const FromModule &) { return Verdict::Accepted; }),
                         artifacts.source));
  if (outcome.verdict() != Verdict::Accepted)
    return statusOf(outcome.verdict());
  if (int code = run(artifacts, rootTiming, outcome)) {
    outcome.failed();
    return code == usage ? usage : statusOf(outcome.verdict());
  }
  outcome.see(std::visit(llvm::makeVisitor(
                             [&](const Executable &executable) {
                               IDR_ZONE_IN("link", Link);
                               mlir::TimingScope linkTiming = rootTiming.nest("link");
                               return link(artifacts, executable);
                             },
                             [](const Archive &) { return Verdict::Accepted; }),
                         artifacts.product));
  return statusOf(outcome.verdict());
}

// The report at `path`, kept only once it is written whole.
static bool writeReport(llvm::StringRef path, const Outcome &outcome) {
  std::error_code error;
  llvm::ToolOutputFile file(path, error, llvm::sys::fs::OF_Text);
  if (error) {
    cannotWrite(path, error);
    return false;
  }
  outcome.write(file.os());
  file.os().flush();
  if (std::error_code written = file.os().error()) {
    file.os().clear_error();
    cannotWrite(path, written);
    return false;
  }
  file.keep();
  return true;
}

std::string idr::driver::frontendBeside(const char *argv0) {
  std::string self =
      llvm::sys::fs::getMainExecutable(argv0, reinterpret_cast<void *>(&frontendBeside));
  llvm::SmallString<256> path(llvm::sys::path::parent_path(self));
  llvm::sys::path::append(path, "idris-mlir-front");
  return path.str().str();
}

int idr::driver::compile(llvm::StringRef frontendPath, Artifacts &artifacts) {
  // The compilation as one span of the trace, however it ends.
  IDR_ZONE_IN("compile", Driver);
  mlir::DefaultTimingManager timings;
  mlir::applyDefaultTimingManagerCLOptions(timings);
  mlir::TimingScope rootTiming = timings.getRootScope();
  Outcome outcome;
  int status = chain(frontendPath, artifacts, outcome, rootTiming);
  // Whatever the status: the report says why a compilation failed. One that
  // cannot be written fails the compilation, which then keeps nothing.
  if (artifacts.report && !writeReport(*artifacts.report, outcome))
    return failure;
  if (status == ok)
    artifacts.keep();
  return status;
}
