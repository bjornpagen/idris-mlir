// idr-target: the module's target, decided once. The triple is the build's
// (the runtime is built for it, and its bitcode joins the program), the CPU
// and extra features the pass's options; LLVM derives the rest, so the
// features a CPU name stands for and the data layout are LLVM's own.

#include "idr/Idr.h"
#include "idr/Target.h"

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

unsigned idr::vectorBits(ModuleOp module) {
  auto target = module->getAttrOfType<LLVM::TargetAttr>(LLVM::LLVMDialect::getTargetAttrName());
  if (!target)
    return 128;
  LLVM::TargetFeaturesAttr features = target.getFeatures();
  auto has = [&](StringRef feature) { return features && features.contains(feature); };
  if (llvm::Triple(target.getTriple().getValue()).isX86())
    return has("+avx512f") ? 512 : has("+avx") ? 256 : 128;
  return 128;
}
