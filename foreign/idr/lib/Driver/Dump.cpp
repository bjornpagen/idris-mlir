// --dump-dir as an instrumentation of the driver's one manager.

#include "idr/Driver/Compile.h"

#include "idr/Driver/Report.h"

#include "mlir/IR/Operation.h"
#include "mlir/IR/OperationSupport.h"
#include "mlir/Pass/Pass.h"

#include "llvm/ADT/SmallString.h"
#include "llvm/Support/FormatVariadic.h"
#include "llvm/Support/Path.h"
#include "llvm/Support/raw_ostream.h"

#include <system_error>

using namespace idr::driver;

void DumpAfterEachPass::runBeforePipeline(std::optional<mlir::OperationName>,
                                          const PipelineParentInfo &) {
  ++depth;
}

void DumpAfterEachPass::runAfterPipeline(std::optional<mlir::OperationName>,
                                         const PipelineParentInfo &) {
  --depth;
}

// A nested manager has no argument of its own, so its dump is named by its
// first pass. Every pipeline of the group begins with that pass, and
// nothing in a pipeline runs before its first pass begins, so the first
// pass to begin under the adaptor, on whichever thread, is the first pass
// of the group.
void DumpAfterEachPass::runBeforePass(mlir::Pass *pass, mlir::Operation *) {
  if (depth == 0) {
    running = pass;
    firstNested.clear();
    return;
  }
  if (running && running->getArgument().empty() && firstNested.empty())
    firstNested = pass->getArgument().str();
}

void DumpAfterEachPass::runAfterPass(mlir::Pass *pass, mlir::Operation *op) {
  if (depth != 0)
    return;
  running = nullptr;
  llvm::StringRef name = pass->getArgument();
  if (name.empty())
    name = firstNested;
  if (name.empty() || writeFailed)
    return;
  llvm::SmallString<128> path(directory);
  llvm::sys::path::append(path, llvm::formatv("{0:02}-{1}.mlir", written + 1, name).str());
  std::error_code error;
  llvm::raw_fd_ostream out(path, error);
  if (error) {
    cannotWrite(path, error);
    writeFailed = true;
    return;
  }
  op->print(out, mlir::OpPrintingFlags().enableDebugInfo().printNameLocAsPrefix());
  ++written;
}
