// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// One compilation, the whole chain: the frontend for Idris source, the
// pipeline and LLVM in process, and the link by the pinned clang, each
// timed under one root, so that -mlir-timing reports the whole command.
#ifndef IDR_DRIVER_COMPILE_H
#define IDR_DRIVER_COMPILE_H

#include "idr/Driver/Artifacts.h"
// The target entry's link flags, an X-macro.
#include "idr/TargetEntry.h"

#include "mlir/IR/OperationSupport.h"
#include "mlir/Pass/PassInstrumentation.h"

#include "llvm/ADT/StringRef.h"

#include <optional>
#include <string>

namespace mlir {
class TimingScope;
} // namespace mlir

namespace llvm {
class Target;
class Triple;
} // namespace llvm

namespace idr::driver {

// What links a program for the target entry, after its object, the runtime
// and -o: --target with the triple, then the entry's executable and
// program link flags and GMP. The link and --print-link-flags read this one
// list.
inline constexpr llvm::StringLiteral linkFlags[] = {
#define IDR_LINK_FLAG(flag) flag,
    IDRIS_MLIR_LINK_FLAGS(IDR_LINK_FLAG)
#undef IDR_LINK_FLAG
};

// idris-mlir-front beside this executable, by its real path: the build
// links the frontend there, and a copy of idris-mlir alone runs no other
// frontend, nor one found on PATH.
std::string frontendBeside(const char *argv0);

// The chain, from the input to the artifacts, which are kept only once
// every step succeeded; an exit status.
int compile(llvm::StringRef frontendPath, Input kind, Artifacts &artifacts);

// The module at `modulePath` through the pipeline and LLVM into the object
// at `objectPath`, each pass and stage timed under `rootTiming`. An exit
// status.
int run(llvm::StringRef modulePath, llvm::StringRef objectPath, mlir::TimingScope &rootTiming);

// LLVM's target for the triple, with its code generator and assembly
// parser (the runtime carries inline assembly) initialized; null, reported,
// when LLVM has none.
const llvm::Target *nativeTarget(const llvm::Triple &triple);

// --dump-dir: writes `<NN>-<name>.mlir` into `directory` after each
// top-level pass, NN from 01 with no gap. A top-level pass is one added to
// the manager itself: the passes of a nested manager and of a pipeline a
// pass runs itself are deeper, and never dump. A nested manager's dump is
// named after the first pass it ran, and one that ran none writes no file.
// The instrumentor calls every hook under one lock, so the plain counters
// are never written by two threads at once.
class DumpAfterEachPass final : public mlir::PassInstrumentation {
public:
  explicit DumpAfterEachPass(llvm::StringRef directory) : directory(directory.str()) {}

  void runBeforePipeline(std::optional<mlir::OperationName> name,
                         const PipelineParentInfo &parentInfo) override;
  void runAfterPipeline(std::optional<mlir::OperationName> name,
                        const PipelineParentInfo &parentInfo) override;
  void runBeforePass(mlir::Pass *pass, mlir::Operation *op) override;
  void runAfterPass(mlir::Pass *pass, mlir::Operation *op) override;

  // Whether a dump could not be written.
  bool failed() const { return writeFailed; }

private:
  std::string directory;
  // The pipelines open now, below the manager's own.
  unsigned depth = 0;
  // The top-level pass running, and the first pass it ran in a nested
  // manager.
  mlir::Pass *running = nullptr;
  std::string firstNested;
  unsigned written = 0;
  bool writeFailed = false;
};

} // namespace idr::driver

#endif // IDR_DRIVER_COMPILE_H
