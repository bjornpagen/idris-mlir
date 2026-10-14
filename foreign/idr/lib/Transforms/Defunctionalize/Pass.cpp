// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-defunctionalize: closures and suspensions of known labels become sums.
//
// The analysis of labels decides every key first; a key that cannot become
// a sum is a value nothing lowers, so the program is rejected where the
// analysis lost it, before anything changes. Otherwise the sums are
// declared and one full dialect conversion gives every slot its sum's type:
// under its target no closure, suspension or apply is legal, nor any value,
// signature or field of a key until it has its sum's type. Folding is off
// in the driver: a closure or a suspension folded into a constant there
// would be a value the key decision never saw; canonicalize follows this
// pass. Then the labels of memo sums that must run at every force are
// marked, and every type being final, the boxes that make each cell fit
// are made.

#include "idr/IR/IdrDialect.h"
#include "idr/Analysis/Labels.h"
#include "idr/IR/Layout.h"
#include "idr/Transforms/Defunctionalize.h"

#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Transforms/DialectConversion.h"

#include "llvm/ADT/STLExtras.h"

namespace idr {
#define GEN_PASS_DEF_IDRDEFUNCTIONALIZE
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace {

using idr::defunctionalize::SlotTypeConverter;
using idr::defunctionalize::Slots;
using idr::defunctionalize::UnknownKey;

void reportUnknown(const UnknownKey &key) {
  if (key.lazy)
    key.at->emitError() << "unsupported (laziness): a suspension reaches '" << key.at->getName()
                        << "', where the analysis of its labels loses it";
  else
    key.at->emitError() << "unsupported (runtime closure): a closure reaches '"
                        << key.at->getName() << "', where the analysis of its labels loses it";
}

// What has its slot's type, and owes no move into another slot. The
// callbacks outlive this call, so they hold the converter and the key
// decision by address.
void addTarget(ConversionTarget &target, SlotTypeConverter &types) {
  SlotTypeConverter *converter = &types;
  Slots *slots = &types.slots();
  // A closure or a suspension is a source of its own key, so its key is
  // never empty, and a key left as it is was refused: none survives, nor
  // an apply, nor an evaluated suspension, which is its memo sum's forced
  // state.
  target.addIllegalOp<idr::ClosureOp, idr::SuspendOp, idr::ApplyOp, idr::DelayOp>();
  target.addLegalOp<idr::DataOp, ModuleOp>();
  target.addDynamicallyLegalOp<idr::FuncOp>([=](idr::FuncOp fn) {
    if (fn.getFunctionType() != slots->functionType(fn))
      return false;
    for (Block &block : fn.getBody())
      if (!llvm::all_of(block.getArguments(), [&](Value arg) { return converter->legal(arg); }))
        return false;
    return true;
  });
  target.addDynamicallyLegalOp<idr::CtorOp>([=](idr::CtorOp ctor) {
    return llvm::equal(ctor.getFieldTypes().getAsValueRange<TypeAttr>(), slots->fieldTypes(ctor));
  });
  target.addDynamicallyLegalOp<idr::ConstantOp>([=](idr::ConstantOp constant) {
    return converter->legal(constant.getResult()) &&
           !slots->labels().holdsClosure(constant.getValue());
  });
  target.addDynamicallyLegalOp<idr::ForceOp>([=](idr::ForceOp force) {
    return !idr::isLazyType(force.getSuspension().getType()) &&
           converter->legal(force.getResult());
  });
  target.markUnknownOpDynamicallyLegal([=](Operation *op) { return converter->legal(op); });
}

struct Defunctionalize : idr::impl::IdrDefunctionalizeBase<Defunctionalize> {
  void runOnOperation() override {
    ModuleOp module = getOperation();
    SymbolTable &symbols = getAnalysis<SymbolTable>();
    idr::Labels &labels = getAnalysis<idr::Labels>();
    if (labels.failed()) {
      module.emitError("internal error: idr-defunctionalize: the analysis of labels did not "
                       "converge");
      return signalPassFailure();
    }
    Slots slots(module, labels, symbols);
    SmallVector<UnknownKey> unknown = slots.unknownKeys();
    if (!unknown.empty()) {
      llvm::for_each(unknown, reportUnknown);
      return signalPassFailure();
    }
    bool keyed = !slots.keys().empty();
    if (keyed && failed(convert(module, slots)))
      return signalPassFailure();
    idr::defunctionalize::markByName(module, symbols);
    unsigned boxed = idr::layout::fit(module);
    numSums += static_cast<uint64_t>(llvm::count_if(
        slots.keys(), [&](const auto &entry) { return slots.isConverted(entry.first); }));
    numClosures += slots.numClosures();
    numBoxed += boxed;
    if (!keyed && boxed == 0)
      markAllAnalysesPreserved();
  }

  // The sums declared, then every slot given its type by one conversion of
  // the whole module.
  LogicalResult convert(ModuleOp module, Slots &slots) {
    if (failed(idr::defunctionalize::declareSums(module, slots)))
      return failure();
    SlotTypeConverter converter(slots);
    ConversionTarget target(getContext());
    addTarget(target, converter);
    RewritePatternSet patterns(&getContext());
    idr::defunctionalize::populateDefunctionalizePatterns(patterns, converter);
    idr::defunctionalize::populateCallOpTypeConversionPattern(patterns, converter);
    idr::defunctionalize::populateReturnOpTypeConversionPattern(patterns, converter);
    // With rollback, erasures wait for the end, so the values and operands
    // the key decision is indexed by stay distinct for the whole run.
    ConversionConfig config;
    config.allowPatternRollback = true;
    config.foldingMode = DialectConversionFoldingMode::Never;
    if (succeeded(applyFullConversion(module, target, std::move(patterns), config)))
      return success();
    return module.emitError("internal error: idr-defunctionalize: the conversion left an op the "
                            "target does not accept");
  }
};

} // namespace
