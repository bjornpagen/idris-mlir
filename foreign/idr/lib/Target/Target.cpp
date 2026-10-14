// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// MLIR's side of the target: idr-target, which decides it once, and what
// later passes read of it. The triple and the CPU are the build's (the
// runtime is built for the triple, and its bitcode joins the program);
// LLVM derives the rest, so the features the CPU name stands for and the
// data layout are LLVM's own.

#include "idr/Target/Target.h"

#include "mlir/Dialect/DLTI/DLTI.h"
#include "mlir/Dialect/LLVMIR/LLVMAttrs.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/Target/LLVMIR/Import.h"
#include "mlir/Target/LLVMIR/Transforms/TargetUtils.h"

#include "llvm/ADT/SmallVectorExtras.h"
#include "llvm/MC/MCSubtargetInfo.h"
#include "llvm/TargetParser/Triple.h"

using namespace mlir;

namespace idr {
#define GEN_PASS_DEF_IDRTARGET
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

namespace {

struct TargetPass : idr::impl::IdrTargetBase<TargetPass> {
  using IdrTargetBase::IdrTargetBase;

  // The steps of LLVM's target-to-features and target-to-data-layout passes,
  // written out: nested, each of them and this pass after them would verify
  // the whole unoptimized module again. The pass sets only the module's own
  // attributes, so it preserves every analysis and the manager skips the
  // verifier after it.
  void runOnOperation() override {
    ModuleOp module = getOperation();
    MLIRContext *ctx = &getContext();
    LLVM::detail::initializeBackendsOnce();
    auto target = LLVM::TargetAttr::get(ctx, StringAttr::get(ctx, IDRIS_MLIR_TARGET_TRIPLE),
                                        StringAttr::get(ctx, IDRIS_MLIR_TARGET_CPU),
                                        LLVM::TargetFeaturesAttr());
    FailureOr<std::unique_ptr<llvm::TargetMachine>> machine =
        LLVM::detail::getTargetMachine(target);
    if (failed(machine)) {
      module.emitError() << "failed to obtain llvm::TargetMachine for " << target;
      return signalPassFailure();
    }
    SmallVector<std::string> features = llvm::map_to_vector(
        (*machine)->getMCSubtargetInfo().getEnabledProcessorFeatures(),
        [](const llvm::SubtargetFeatureKV *feature) { return "+" + std::string(feature->key()); });
    target = LLVM::TargetAttr::get(
        ctx, target.getTriple(), target.getChip(),
        LLVM::TargetFeaturesAttr::get(ctx, llvm::map_to_vector(features, [](const std::string &feature) {
          return StringRef(feature);
        })));
    module->setAttr(LLVM::LLVMDialect::getTargetAttrName(), target);

    FailureOr<llvm::DataLayout> layout = LLVM::detail::getDataLayout(target);
    if (failed(layout)) {
      module.emitError() << "failed to obtain llvm::DataLayout for " << target;
      return signalPassFailure();
    }
    DataLayoutSpecInterface spec = translateDataLayout(*layout, ctx);
    if (auto existing = module->getAttrOfType<DataLayoutSpecInterface>(DLTIDialect::kDataLayoutAttrName))
      spec = existing.combineWith({spec});
    module->setAttr(DLTIDialect::kDataLayoutAttrName, spec);
    markAllAnalysesPreserved();
  }
};

} // namespace

unsigned idr::target::vectorBits(ModuleOp module) {
  auto target = module->getAttrOfType<LLVM::TargetAttr>(LLVM::LLVMDialect::getTargetAttrName());
  if (!target)
    return 128;
  LLVM::TargetFeaturesAttr features = target.getFeatures();
  auto has = [&](StringRef feature) { return features && features.contains(feature); };
  if (llvm::Triple(target.getTriple().getValue()).isX86())
    return has("+avx512f") ? 512 : has("+avx") ? 256 : 128;
  return 128;
}
