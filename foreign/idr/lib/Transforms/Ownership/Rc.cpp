// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-rc: every reference made explicit. Five steps, each on what the one
// before left, on a program in the first stage:
//   1. every loop over buffers whose elements hold references becomes
//      scf.for loops, and the boundaries with upstream's buffer ops are
//      marked (an adopt after each allocation, a give before each counted
//      store);
//   2. reset/reuse decides where dead boxes are taken apart, and borrow
//      inference, which keeps every parameter a reuse takes apart owned,
//      writes the owned grades into every signature, from which point the
//      program is in the owned stage;
//   3. each function is placed, nested: the reuse rewrite, then the counts,
//      which read the grades of its own signature and its callees';
//   4. exclusivity, which reads the dups placement made, is solved; the
//      functions whose callers disagree on a grade, and the ones their
//      copies call, are the keys, each copied once; the program with its
//      copies is solved, the solve sending each call of a key or a copy to
//      the copy if it gives exclusive values and to the original if not,
//      and each call goes where that solve sent it, which makes it the
//      solve of the program as the calls now stand; then the excl grades
//      it proved go into every signature;
//   5. each function is committed, nested, and the copies and originals
//      nothing calls any more are erased.
// Steps 2 and 4 write signatures; steps 3 and 5 rewrite bodies, while no
// signature changes. A nested run leaves no analysis of the program behind,
// so each step takes what it reads afresh.
#include "idr/Analysis/Ownership.h"
#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Ownership.h"
#include "idr/IR/TypeGraph.h"
#include "idr/Transforms/Ownership.h"

#include "mlir/Dialect/Affine/IR/AffineOps.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
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
    idr::ProgramOp program = getOperation();
    if (program.getStage() != idr::Stage::First) {
      program.emitError("idr-rc: internal error: runs on a program in the first stage, not ")
          << idr::stringifyStage(program.getStage());
      return signalPassFailure();
    }
    // Each function on its own, in parallel: what reset/reuse and borrow
    // inference read below is the form placement counts.
    SmallVector<idr::FuncOp> fns(program.getOps<idr::FuncOp>());
    if (failed(failableParallelForEach(&getContext(), fns, own::bufferForms)))
      return signalPassFailure();

    const idr::Reuses reuses(program, getAnalysis<idr::Layouts>());
    {
      const idr::Borrows borrows(program, getAnalysis<SymbolTable>(), reuses);
      numBorrowed += borrows.borrowed();
      own::writeOwnedGrades(program, borrows);
    }
    // The grades are counted from here on, which is what the stage says
    // and the verifier of every nested run below checks.
    program.setStage(idr::Stage::Owned);

    // A nested run leaves no analysis of the program behind, so the table
    // each one reads is taken right before it.
    {
      const idr::CalleeEffects callees{getAnalysis<SymbolTable>()};
      if (failed(runNested(own::createRcPlace(reuses, callees))))
        return signalPassFailure();
    }

    SymbolTable &symbols = getAnalysis<SymbolTable>();
    own::shareTainted(program, symbols);
    // The solve of the program as placement left it decides the keys; the
    // solve of the program with their copies, which sends each call where
    // it gives, is the one the grades come from. With no copy the first is
    // that solve too.
    FailureOr<idr::Exclusivity> solved = solve(own::Copies());
    if (failed(solved))
      return signalPassFailure();
    FailureOr<own::Copies> copies = own::specializeOnGrade(program, *solved, symbols);
    if (failed(copies))
      return signalPassFailure();
    if (!copies->of.empty()) {
      if (failed(solved = solve(*copies)))
        return signalPassFailure();
      own::redirectCalls(program, *solved);
    }
    own::writeExclusiveGrades(program, *solved, symbols);

    if (failed(runNested(own::createRcCommit(*solved, symbols))))
      return signalPassFailure();
    own::eraseUnused(program, getAnalysis<SymbolTable>(), *copies);
    count(program);
    // No data type changed, and every symbol came and went through the table.
    markAnalysesPreserved<idr::TypeGraph, idr::Layouts, SymbolTable>();
  }

  // The solve of the program as it stands, with `copies`; failure, which
  // is reported here, when MLIR's solver fails.
  FailureOr<idr::Exclusivity> solve(const idr::ownership::Copies &copies) {
    FailureOr<idr::Exclusivity> solved = idr::Exclusivity::solve(getOperation(), copies);
    if (failed(solved))
      getOperation().emitError("idr-rc: internal error: the exclusivity solve failed");
    return solved;
  }

  // `pass` on every function of the program, under a nested manager, which
  // runs the functions in parallel.
  LogicalResult runNested(std::unique_ptr<Pass> pass) {
    OpPassManager nested(idr::ProgramOp::getOperationName());
    nested.nest<idr::FuncOp>().addPass(std::move(pass));
    return runPipeline(nested, getOperation());
  }

  // What the steps made, in one walk once they are all done.
  void count(idr::ProgramOp program) {
    unsigned exclusive = 0, takes = 0, reuses = 0, dups = 0, drops = 0;
    auto excl = [](Value value) { return idr::isExclusive(value.getType()) ? 1u : 0u; };
    program.walk([&](Block *block) {
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
