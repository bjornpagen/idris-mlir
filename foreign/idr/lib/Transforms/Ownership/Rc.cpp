// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-rc: every reference made explicit. Five steps, each on what the one
// before left:
//   1. a module already in the owned stage is refused; every loop over
//      buffers whose elements hold references becomes scf.for loops, and
//      the boundaries with upstream's buffer ops are marked (an adopt after
//      each allocation, a give before each counted store);
//   2. reset/reuse decides where dead boxes are taken apart, and borrow
//      inference, which keeps every parameter a reuse takes apart owned,
//      writes the owned grades into every signature;
//   3. each function is placed, nested: the reuse rewrite, then the counts,
//      which read the grades of its own signature and its callees';
//   4. exclusivity, which reads the dups placement made, is solved; each
//      round gathers the functions whose callers disagree on a grade as
//      keys, makes each key's copy once and sends it the calls that agree,
//      until a round sends none; then the excl grades go into every
//      signature;
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
#include "mlir/IR/Threading.h"
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
    // Each function on its own, in parallel: what reset/reuse and borrow
    // inference read below is the form placement counts.
    SmallVector<idr::FuncOp> fns(module.getOps<idr::FuncOp>());
    if (failed(failableParallelForEach(&getContext(), fns, own::bufferForms)))
      return signalPassFailure();

    if (failed(getAnalysis<idr::Layouts>().valid()))
      return signalPassFailure();
    getAnalysis<idr::Reuses>();
    idr::Borrows &borrows = getAnalysis<idr::Borrows>();
    numBorrowed += borrows.borrowed();
    own::writeOwnedGrades(module, borrows);

    // What the nested placement reads is computed here, right before it.
    getAnalysis<SymbolTable>();
    if (failed(runNested(own::createRcPlace())))
      return signalPassFailure();

    SymbolTable &symbols = getAnalysis<SymbolTable>();
    own::shareTainted(module, symbols);
    // A round's copies change what the solve sees, so it is solved again,
    // the table kept: the copies went in through it. A call is redirected
    // once and each key's copy made once, so the rounds end with the first
    // that redirects nothing.
    AnalysisManager::PreservedAnalyses kept;
    kept.preserve<SymbolTable>();
    own::Copies copies;
    for (;;) {
      idr::Exclusivity &solved = getAnalysis<idr::Exclusivity>();
      if (solved.failed()) {
        module.emitError("idr-rc: internal error: the exclusivity solve failed");
        return signalPassFailure();
      }
      FailureOr<bool> redirected = own::specializeOnGrade(module, solved, symbols, copies);
      if (failed(redirected))
        return signalPassFailure();
      if (!*redirected) {
        own::writeExclusiveGrades(module, solved, symbols);
        break;
      }
      getAnalysisManager().invalidate(kept);
    }

    if (failed(runNested(own::createRcCommit())))
      return signalPassFailure();
    own::eraseUnusedOriginals(module, getAnalysis<SymbolTable>(), copies);
    count(module);
    // No data type changed, and every symbol came and went through the table.
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
