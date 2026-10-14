// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-rc: every reference made explicit. Five steps, each on what the one
// before left:
//   1. a module already in the owned stage is refused;
//   2. reset/reuse decides where dead boxes are taken apart, and borrow
//      inference, which keeps every parameter a reuse takes apart owned,
//      writes the owned grades into every signature;
//   3. each function is placed, nested: the reuse rewrite, then the counts,
//      which read the grades of its own signature and its callees';
//   4. exclusivity, which reads the dups placement made, is solved, a
//      function is copied where its callers disagree on a grade until the
//      solve settles, and the excl grades go into every signature;
//   5. each function is committed, nested, and the originals nothing calls
//      any more are erased.
// Steps 2 and 4 write signatures; steps 3 and 5 rewrite bodies, while no
// signature changes. A nested run leaves no analysis of the module behind,
// so each step takes what it reads afresh.
#include "idr/Analysis/Holds.h"
#include "idr/Analysis/Ownership.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Ownership.h"
#include "idr/IR/TypeGraph.h"
#include "idr/Transforms/Ownership.h"

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Pass/PassManager.h"

namespace idr {
#define GEN_PASS_DEF_IDRRC
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace {

struct Rc : idr::impl::IdrRcBase<Rc> {
  using IdrRcBase::IdrRcBase;

  void runOnOperation() override {
    namespace own = idr::ownership;
    ModuleOp module = getOperation();
    // The grades are the stage, so no attribute restates it.
    if (llvm::any_of(module.getOps<idr::FuncOp>(),
                     [](idr::FuncOp fn) { return own::inOwnedStage(fn); })) {
      module.emitError("idr-rc: the module is already in the owned stage");
      return signalPassFailure();
    }

    if (reuse) {
      if (failed(getAnalysis<idr::Layouts>().valid()))
        return signalPassFailure();
      getAnalysis<idr::Reuses>();
    }
    idr::Borrows &borrows = getAnalysis<idr::Borrows>();
    numBorrowed += borrows.borrowed();
    own::writeOwnedGrades(module, borrows);

    // What the nested placement reads is computed here, right before it.
    getAnalysis<SymbolTable>();
    if (failed(runNested(own::createRcPlace(reuse, sink))))
      return signalPassFailure();

    SymbolTable &symbols = getAnalysis<SymbolTable>();
    // A clone names itself without calling it, which the solver would take
    // for a caller it cannot see; nothing after idr-rc reads it.
    for (idr::FuncOp fn : module.getOps<idr::FuncOp>())
      fn.removeCloneAttr();
    own::shareTainted(module, symbols);
    // Every round redirects a call for good, so the rounds are bounded by
    // the calls; a round past that is a bug here. A round's copies change
    // what the solve sees, so it is solved again, the table kept: the
    // copies went in through it.
    unsigned calls = 0;
    module.walk([&](idr::CallOp) { ++calls; });
    AnalysisManager::PreservedAnalyses kept;
    kept.preserve<SymbolTable>();
    own::Copies copies;
    for (unsigned round = 0;; ++round) {
      idr::Exclusivity &solved = getAnalysis<idr::Exclusivity>();
      if (solved.failed()) {
        module.emitError("idr-rc: internal error: the exclusivity solve failed");
        return signalPassFailure();
      }
      if (!own::specializeOnGrade(module, solved, symbols, copies)) {
        own::writeExclusiveGrades(module, solved, symbols);
        break;
      }
      if (round == calls) {
        module.emitError("idr-rc: specializing on exclusivity did not settle");
        return signalPassFailure();
      }
      getAnalysisManager().invalidate(kept);
    }

    if (failed(runNested(own::createRcCommit())))
      return signalPassFailure();
    own::eraseUnusedOriginals(module, getAnalysis<SymbolTable>(), copies);
    count(module);
    // No idr.data changed, and every symbol came and went through the table.
    markAnalysesPreserved<idr::Holds, idr::TypeGraph, idr::Layouts, SymbolTable>();
  }

  // `pass` on every function of the module, under a nested manager, which
  // runs the functions in parallel.
  LogicalResult runNested(std::unique_ptr<Pass> pass) {
    OpPassManager nested(ModuleOp::getOperationName());
    nested.nest<idr::FuncOp>().addPass(std::move(pass));
    return runPipeline(nested, getOperation());
  }

  // What the steps made, in one walk once they are all done.
  void count(ModuleOp module) {
    unsigned exclusive = 0, takes = 0, reuses = 0, dups = 0, drops = 0;
    auto excl = [](Value value) { return idr::isExclusive(value.getType()) ? 1u : 0u; };
    module.walk([&](Block *block) {
      for (BlockArgument arg : block->getArguments())
        exclusive += excl(arg);
      for (Operation &op : *block) {
        for (Value result : op.getResults())
          exclusive += excl(result);
        // A take counts where its cell goes to a reuse; the takes placement
        // makes only move fields out.
        if (auto take = dyn_cast<idr::TakeOp>(op))
          if (Value cell = take.getToken())
            takes += llvm::any_of(cell.getUsers(), llvm::IsaPred<idr::ReuseOp>) ? 1 : 0;
        reuses += isa<idr::ReuseOp>(op) ? 1 : 0;
        dups += isa<idr::DupOp>(op) ? 1 : 0;
        drops += isa<idr::DropOp>(op) ? 1 : 0;
      }
    });
    numExclusive += exclusive;
    numTakes += takes;
    numReuses += reuses;
    numDups += dups;
    numDrops += drops;
  }
};

} // namespace
