// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-effects: `effects` on every idr.func and every idr.call of a
// defunctionalized module, written as the ready set of idr-optimize writes
// them, component by component, callees first, with nothing optimized
// between: a component's calls out of it take their callees' entries, then
// its members their entry and the calls between them that entry. A call
// carries its callee's fact because what MLIR asks of a call (whether
// canonicalize may erase it, CSE merge it) is asked of the op alone, with
// no symbol table in hand.
//
// Only defunctionalization's label solve knows what an apply runs, or a
// force of a suspension, so a module that still holds one is refused here
// rather than summarized as if it ran nothing.
#include "idr/Transforms/Effects.h"

#include "idr/Analysis/Effects.h"
#include "idr/Analysis/Holds.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Scc.h"

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/SymbolTable.h"
#include "llvm/ADT/STLExtras.h"

namespace idr {
#define GEN_PASS_DEF_IDREFFECTS
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace {

// The first op that runs a closure or a suspension, or null in a
// defunctionalized module.
Operation *runsUnconverted(ModuleOp module) {
  Operation *found = nullptr;
  module.walk([&](Operation *op) {
    auto force = dyn_cast<idr::ForceOp>(op);
    if (!isa<idr::ApplyOp>(op) && !(force && idr::isLazyType(force.getSuspension().getType())))
      return WalkResult::advance();
    found = op;
    return WalkResult::interrupt();
  });
  return found;
}

struct IdrEffectsPass : idr::impl::IdrEffectsBase<IdrEffectsPass> {
  void runOnOperation() override {
    ModuleOp module = getOperation();
    if (Operation *op = runsUnconverted(module)) {
      op->emitError("idr-effects runs on a defunctionalized module, and this op still runs a "
                    "closure or a suspension");
      return signalPassFailure();
    }
    const idr::Holds &holds = getAnalysis<idr::Holds>();
    const SymbolTable &symbols = getAnalysis<SymbolTable>();

    SmallVector<idr::FuncOp> fns(module.getOps<idr::FuncOp>());
    llvm::DenseMap<Operation *, unsigned> positions;
    for (auto [at, fn] : llvm::enumerate(fns))
      positions.try_emplace(fn.getOperation(), static_cast<unsigned>(at));
    SmallVector<SmallVector<unsigned>> successors(fns.size());
    for (auto [at, fn] : llvm::enumerate(fns)) {
      SmallVector<idr::FuncOp> runs;
      fn.getBody().walk([&](Operation *op) {
        if (auto call = dyn_cast<idr::CallOp>(op))
          runs.push_back(symbols.lookup<idr::FuncOp>(call.getCalleeAttr().getAttr()));
        else if (auto force = dyn_cast<idr::ForceOp>(op))
          idr::forcedLabels(force, symbols, runs);
      });
      for (idr::FuncOp target : runs)
        successors[at].push_back(positions.lookup(target.getOperation()));
    }

    for (const SmallVector<unsigned> &component : idr::components(successors)) {
      SmallVector<idr::FuncOp> members;
      for (unsigned at : component)
        members.push_back(fns[at]);
      idr::writeCallEffectsOnReady(members, symbols);
      idr::writeEntriesOnFinal(members, holds, symbols);
    }

    for (idr::FuncOp fn : fns) {
      idr::Effect entry = fn.getEffectsAttr() ? fn.getEffectsAttr().getValue() : idr::anyEffect;
      numIO += idr::bitEnumContainsAny(entry, idr::Effect::io);
      numCrash += idr::bitEnumContainsAny(entry, idr::Effect::crash);
      numDiverge += idr::bitEnumContainsAny(entry, idr::Effect::diverge);
    }
    // Only facts on functions and calls changed.
    markAnalysesPreserved<SymbolTable>();
  }
};

} // namespace
