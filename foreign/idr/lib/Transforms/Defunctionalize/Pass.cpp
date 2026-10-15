// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-defunctionalize: every closure and suspension becomes a constructor of
// a sum, every apply a match over its callee's sum.
//
// The solve finds every slot's labels, with no unknown: every key becomes a
// sum, so the pass refuses nothing, and fails only when the compiler broke
// its own invariant. The effects summary is computed next, over the calls
// and the labels each apply and force runs, so that each memo sum's body is
// set once with its `by_name` labels. Every sum and every remade type is
// made, then each function converts on its own, in parallel, reading the
// decision and a plan of its own values: under its target no closure,
// suspension, apply or evaluated suspension is legal, nor any value,
// signature or constant until it has its slot's type. Folding is off in the
// driver: a closure or a suspension folded into a constant there would be a
// value the decision never saw. Then every function's entry is written,
// and, every type being final, the boxes that make each cell fit are made.

#include "idr/IR/IdrDialect.h"
#include "idr/Analysis/Effects.h"
#include "idr/Analysis/Holds.h"
#include "idr/Analysis/Labels.h"
#include "idr/IR/Layout.h"
#include "idr/Transforms/Defunctionalize.h"

#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/IR/Threading.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Transforms/DialectConversion.h"

#include "llvm/ADT/STLExtras.h"

namespace idr {
#define GEN_PASS_DEF_IDRDEFUNCTIONALIZE
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace {

using idr::defunctionalize::Plan;
using idr::defunctionalize::SlotTypeConverter;
using idr::defunctionalize::Slots;

// What has its slot's type, and owes no move into another slot. The
// callbacks outlive this call, so they hold the converter by address.
void addTarget(ConversionTarget &target, const SlotTypeConverter &types) {
  const SlotTypeConverter *converter = &types;
  const Slots *slots = &types.slots();
  // A closure or a suspension is a constructor of its key's sum, an apply a
  // match, and an evaluated suspension its memo sum's forced state.
  target.addIllegalOp<idr::ClosureOp, idr::SuspendOp, idr::ApplyOp, idr::DelayOp>();
  target.addDynamicallyLegalOp<idr::FuncOp>([=](idr::FuncOp fn) {
    if (fn.getFunctionType() != slots->signature(fn.getSymNameAttr()).converted)
      return false;
    for (Block &block : fn.getBody())
      if (!llvm::all_of(block.getArguments(), [&](Value arg) { return converter->legal(arg); }))
        return false;
    return true;
  });
  target.addDynamicallyLegalOp<idr::ConstantOp>([=](idr::ConstantOp constant) {
    Attribute converted = slots->constantOf(constant);
    return converter->legal(constant.getResult()) &&
           (!converted || converted == constant.getValue());
  });
  target.addDynamicallyLegalOp<idr::ForceOp>([=](idr::ForceOp force) {
    return !idr::isLazyType(force.getSuspension().getType()) &&
           converter->legal(force.getResult());
  });
  target.markUnknownOpDynamicallyLegal([=](Operation *op) { return converter->legal(op); });
}

// One function, from its own plan. With rollback, erasures wait for the end,
// so the values and operands the plan is indexed by stay distinct for the
// whole run.
LogicalResult convert(idr::FuncOp fn, const Slots &slots) {
  MLIRContext *ctx = fn.getContext();
  Plan plan = slots.plan(fn);
  SlotTypeConverter converter(slots, plan);
  ConversionTarget target(*ctx);
  addTarget(target, converter);
  RewritePatternSet patterns(ctx);
  idr::defunctionalize::populateDefunctionalizePatterns(patterns, converter);
  idr::defunctionalize::populateCallOpTypeConversionPattern(patterns, converter);
  idr::defunctionalize::populateReturnOpTypeConversionPattern(patterns, converter);
  ConversionConfig config;
  config.allowPatternRollback = true;
  config.foldingMode = DialectConversionFoldingMode::Never;
  if (succeeded(applyFullConversion(fn.getOperation(), target, std::move(patterns), config)))
    return success();
  return fn.emitError("internal error: idr-defunctionalize: the conversion left an op the "
                      "target does not accept");
}

struct Defunctionalize : idr::impl::IdrDefunctionalizeBase<Defunctionalize> {
  void runOnOperation() override {
    ModuleOp module = getOperation();
    SymbolTable &symbols = getAnalysis<SymbolTable>();
    idr::Labels &labels = getAnalysis<idr::Labels>();
    const idr::Holds &holds = getAnalysis<idr::Holds>();
    idr::ModuleEffects effects(
        module, holds, symbols,
        [&](Operation *op, SmallVectorImpl<idr::FuncOp> &run) {
          for (auto label : labels.runs(op).getAsRange<FlatSymbolRefAttr>())
            run.push_back(labels.function(label.getAttr()));
        });
    Slots slots(module, labels, symbols);
    if (failed(slots.declare([&](idr::FuncOp label) { return effects.byName(label); })))
      return signalPassFailure();
    if (slots.keyed()) {
      SmallVector<idr::FuncOp> functions(module.getOps<idr::FuncOp>());
      if (failed(failableParallelForEach(&getContext(), functions, [&](idr::FuncOp fn) {
            return convert(fn, slots);
          })))
        return signalPassFailure();
    }
    effects.writeEntries();
    numBoxed += idr::layout::fit(module);
    numSums += slots.numSums();
    numConstructors += slots.numConstructors();
    if (slots.largestBoxedSum() > largestBoxedSum)
      largestBoxedSum = slots.largestBoxedSum();
  }
};

} // namespace
