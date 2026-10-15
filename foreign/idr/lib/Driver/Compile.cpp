// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// One compilation, timed and profiled as a whole: the frontend and the link
// as child processes, the pipeline and LLVM in process.

#include "idr/Driver/Compile.h"

#include "idr/Driver/Artifacts.h"
#include "idr/Driver/Options.h"
#include "idr/Driver/Report.h"
#include "idr/Support/Profile.h"

#include "mlir/Support/Timing.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallString.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/Support/FileSystem.h"
#include "llvm/Support/Path.h"
#include "llvm/Support/Program.h"

#include <iterator>
#include <optional>
#include <string>
#include <variant>
#include <vector>

using namespace idr::driver;

// Idris source to the Core and the module the plan names. The frontend
// reads no environment, so its prefix and package directories are its
// arguments. It prints Idris's errors and its own rejections as Idris
// prints them, and exits with this tool's statuses: 3 is the program's and
// passes through; anything else but 0, or a frontend that did not run or
// did not finish, is the compiler's.
static int frontend(llvm::StringRef frontendPath, const FromIdris &idris) {
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
    return failure;
  }
  if (status == ok || status == rejected)
    return status;
  if (status < 0)
    Report() << "internal error: " << frontendPath << " did not finish: " << error;
  else
    Report() << "internal error: " << frontendPath << " exited with status " << status;
  return failure;
}

// The pinned clang links the objects of the program's bins, in their
// order, and the runtime's (what the program did not inline resolves
// there) into the executable, for the target the objects were compiled for.
static int link(const Artifacts &artifacts, const Executable &executable) {
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
    return failure;
  }
  return ok;
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
  int status = std::visit(llvm::makeVisitor(
                              [&](const FromIdris &idris) {
                                IDR_ZONE_IN("frontend", Driver);
                                mlir::TimingScope frontendTiming = rootTiming.nest("frontend");
                                return frontend(frontendPath, idris);
                              },
                              [](const FromModule &) { return ok; }),
                          artifacts.source);
  if (status != ok)
    return status;
  if (int code = run(artifacts, rootTiming))
    return code;
  status = std::visit(llvm::makeVisitor(
                          [&](const Executable &executable) {
                            IDR_ZONE_IN("link", Link);
                            mlir::TimingScope linkTiming = rootTiming.nest("link");
                            return link(artifacts, executable);
                          },
                          [](const Archive &) { return ok; }),
                      artifacts.product);
  if (status != ok)
    return status;
  artifacts.keep();
  return ok;
}
