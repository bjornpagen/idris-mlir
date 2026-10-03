// idr-target: the module's target, decided once. The triple is the build's
// (the runtime is built for it, and its bitcode joins the program), the CPU
// and extra features the pass's options; LLVM derives the rest, so the
// features a CPU name stands for and the data layout are LLVM's own.

#include "idr/Idr.h"

#include "mlir/Dialect/DLTI/DLTI.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Target/LLVMIR/Transforms/Passes.h"

using namespace mlir;

namespace idr {
#define GEN_PASS_DEF_IDRTARGET
#include "idr/Passes.h.inc"
} // namespace idr

namespace {

struct Target : idr::impl::IdrTargetBase<Target> {
  using IdrTargetBase::IdrTargetBase;

  void runOnOperation() override {
    ModuleOp module = getOperation();
    MLIRContext *ctx = &getContext();
    auto extra = features.empty() ? LLVM::TargetFeaturesAttr()
                                  : LLVM::TargetFeaturesAttr::get(ctx, features);
    module->setAttr(LLVM::LLVMDialect::getTargetAttrName(),
                    LLVM::TargetAttr::get(ctx, StringAttr::get(ctx, IDRIS_MLIR_TARGET_TRIPLE),
                                          StringAttr::get(ctx, cpu), extra));
    OpPassManager derive(ModuleOp::getOperationName());
    derive.addPass(LLVM::createLLVMTargetToTargetFeatures());
    derive.addPass(LLVM::createLLVMTargetToDataLayout());
    if (failed(runPipeline(derive, module)))
      signalPassFailure();
  }
};

} // namespace
