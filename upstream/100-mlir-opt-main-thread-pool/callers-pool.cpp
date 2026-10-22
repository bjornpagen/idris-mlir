// MlirOptMain runs its input on the thread pool its caller gives it: a pass
// records the pool of the context it runs in, which is the caller's. It
// prints "ok" with the patch; at the pin it does not build, since no
// caller can give MlirOptMain a pool.
// Built against the toolchain's MLIR:
//   clang++ -std=c++17 callers-pool.cpp $(llvm-config --cxxflags --ldflags) libMLIR*.a $(llvm-config --libs --system-libs)
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/DialectRegistry.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Tools/mlir-opt/MlirOptMain.h"
#include "llvm/Support/MemoryBuffer.h"
#include "llvm/Support/ThreadPool.h"
#include "llvm/Support/Threading.h"
#include "llvm/Support/raw_ostream.h"
#include <cstdio>
#include <memory>
#include <string>

namespace {
struct RecordPool
    : public mlir::PassWrapper<RecordPool, mlir::OperationPass<mlir::ModuleOp>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(RecordPool)
  explicit RecordPool(llvm::ThreadPoolInterface **seen) : seen(seen) {}
  void runOnOperation() override {
    mlir::MLIRContext &context = getContext();
    *seen = context.isMultithreadingEnabled() ? &context.getThreadPool() : nullptr;
  }
  llvm::ThreadPoolInterface **seen;
};
} // namespace

int main() {
  mlir::registerPassManagerCLOptions();
  mlir::DialectRegistry registry;
  llvm::StdThreadPool pool(llvm::hardware_concurrency(2));
  llvm::ThreadPoolInterface *seen = nullptr;
  mlir::MlirOptMainConfig config;
  config.setThreadPool(&pool);
  config.setPassPipelineSetupFn([&seen](mlir::PassManager &pm) {
    pm.addPass(std::make_unique<RecordPool>(&seen));
    return mlir::success();
  });
  std::string output;
  llvm::raw_string_ostream os(output);
  bool ran = mlir::succeeded(mlir::MlirOptMain(
      os, llvm::MemoryBuffer::getMemBuffer("module {}"), registry, config));
  bool ok = ran && seen == &pool;
  std::puts(ok ? "ok" : "wrong");
  return ok ? 0 : 1;
}
