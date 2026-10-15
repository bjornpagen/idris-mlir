// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// MLIR's side of the target: idr-target, which decides it once. The triple
// and the CPU are the build's (the runtime is built for the triple, and its
// bitcode joins the program); LLVM derives the rest, so the features the
// CPU name stands for, the data layout and the width of the vector
// registers are LLVM's own, and nothing about a target is decided here.

#include "idr/Target/Target.h"

#include "mlir/Dialect/DLTI/DLTI.h"
#include "mlir/Dialect/LLVMIR/LLVMAttrs.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/Interfaces/DataLayoutInterfaces.h"
#include "mlir/Target/LLVMIR/Import.h"
#include "mlir/Target/LLVMIR/Transforms/TargetUtils.h"

#include "llvm/ADT/SmallVectorExtras.h"
#include "llvm/Analysis/TargetTransformInfo.h"
#include "llvm/IR/DerivedTypes.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"
#include "llvm/MC/MCSubtargetInfo.h"
#include "llvm/TargetParser/Triple.h"

using namespace mlir;

namespace idr {
#define GEN_PASS_DEF_IDRTARGET
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

namespace {

// The width in bits of the machine's fixed vector registers, as LLVM's
// cost model answers it for the machine's CPU and features: asked of a
// function with no attributes of its own, which the machine's subtarget
// then describes.
std::uint64_t vectorWidth(const llvm::TargetMachine &machine) {
  llvm::LLVMContext context;
  llvm::Module scratch("idr-target", context);
  scratch.setTargetTriple(machine.getTargetTriple());
  scratch.setDataLayout(machine.createDataLayout());
  llvm::Function *function =
      llvm::Function::Create(llvm::FunctionType::get(llvm::Type::getVoidTy(context), false),
                             llvm::GlobalValue::ExternalLinkage, "f", scratch);
  return machine.getTargetTransformInfo(*function)
      .getRegisterBitWidth(llvm::TargetTransformInfo::RGK_FixedWidthVector)
      .getFixedValue();
}

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

    // The facts the schedules read, held once, in the module: the CPU's
    // vector width, which the lanes of a loop over an array follow.
    auto width = DataLayoutEntryAttr::get(
        StringAttr::get(ctx, idr::target::vectorWidthKey),
        IntegerAttr::get(IntegerType::get(ctx, 64),
                         static_cast<std::int64_t>(vectorWidth(**machine))));
    auto cpu = DataLayoutEntryAttr::get(StringAttr::get(ctx, idr::target::cpuDevice),
                                        TargetDeviceSpecAttr::get(ctx, {width}));
    module->setAttr(DLTIDialect::kTargetSystemDescAttrName, TargetSystemSpecAttr::get(ctx, {cpu}));
    markAllAnalysesPreserved();
  }
};

} // namespace
