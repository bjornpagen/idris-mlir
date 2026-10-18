// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-defunctionalize: every closure and suspension becomes a constructor of
// a sum, every apply a match over its callee's sum, every force a call of
// its memo sum's dispatch function.
//
// The solve finds every slot's labels, with no unknown: every key becomes a
// sum, so the pass refuses nothing, and fails only when the compiler broke
// its own invariant. The labels whose runs the outside observes are found
// next, over the calls and the labels each apply and force runs, so that
// each memo sum is made once with its `by_name` labels. The decision is
// made whole, every sum and every dispatch function with it, then each
// function the program had converts on its own, in parallel, reading the
// decision and a plan of its own values: under its target no closure,
// suspension, apply, force or evaluated suspension is legal, nor any value,
// signature or constant of a closure or a suspension until it has its
// slot's type. Folding is off in the driver: a closure or a suspension
// folded into a constant there would be a value the decision never saw.
// Then the types that hold a slot are made anew, every type is final, and
// the boxes are decided: the program is first-order.

#include "idr/IR/IdrDialect.h"
#include "idr/Analysis/Effects.h"
#include "idr/Analysis/Labels.h"
#include "idr/IR/Layout.h"
#include "idr/IR/TypeGraph.h"
#include "idr/Transforms/Defunctionalize.h"
#include "idr/Transforms/Pipeline.h"

#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/IR/Threading.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Transforms/DialectConversion.h"

#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"

#include <algorithm>

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
  // match, a force a call, and an evaluated suspension its memo sum's
  // Forced state.
  target.addIllegalOp<idr::ClosureOp, idr::SuspendOp, idr::ApplyOp, idr::ForceOp,
                      idr::DelayOp>();
  target.addDynamicallyLegalOp<idr::FuncOp>([=](idr::FuncOp fn) {
    return fn.getFunctionType() == slots->signature(fn.getSymNameAttr()).converted &&
           llvm::all_of(fn.getArguments(), [&](Value arg) { return converter->legal(arg); });
  });
  target.addDynamicallyLegalOp<idr::ConstantOp>([=](idr::ConstantOp constant) {
    Attribute converted = slots->constantOf(constant);
    return converter->legal(constant.getResult()) &&
           (!converted || converted == constant.getValue());
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
  void runOnProgram(idr::ProgramOp program) override {
    SymbolTable &symbols = getAnalysis<SymbolTable>();
    idr::Labels &labels = getAnalysis<idr::Labels>();
    llvm::DenseSet<idr::FuncOp> observed = idr::observableRuns(
        program, symbols,
        [&](idr::RunsLabelsOpInterface runner, SmallVectorImpl<idr::FuncOp> &run) {
          for (auto label : labels.runs(runner).getAsRange<FlatSymbolRefAttr>())
            run.push_back(labels.function(label.getAttr()));
        });
    // The functions the program had: the decision adds a dispatch function
    // for each memo sum, made converted.
    SmallVector<idr::FuncOp> functions(program.getOps<idr::FuncOp>());
    FailureOr<std::unique_ptr<Slots>> slots = Slots::decide(
        program, labels, symbols, [&](idr::FuncOp label) { return observed.contains(label); });
    if (failed(slots))
      return signalPassFailure();
    const Slots &decision = **slots;
    if (failed(failableParallelForEach(&getContext(), functions, [&](idr::FuncOp fn) {
          return convert(fn, decision);
        })))
      return signalPassFailure();
    if (failed((*slots)->remake()))
      return signalPassFailure();
    FailureOr<unsigned> boxed = idr::layout::fit(program);
    if (failed(boxed))
      return signalPassFailure();
    numBoxed += *boxed;
    numSums += decision.numSums();
    numConstructors += decision.numConstructors();
    // The type graph of the final types, built here: one cached from before
    // this pass would hold the types it replaced.
    idr::TypeGraph graph(program);
    unsigned largest = 0;
    for (idr::DataType data : graph.declarations())
      if (data.isClosures() && graph.boxed(data))
        largest = std::max(largest, static_cast<unsigned>(data.getCtors().size()));
    if (largest > largestBoxedSum)
      largestBoxedSum = largest;
  }
};

} // namespace
