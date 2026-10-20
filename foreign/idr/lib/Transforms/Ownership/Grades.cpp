// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-rc-grades: the decisions counting takes on the program, the owned
// grades they give every signature, and each body placed under them. The
// boundaries with upstream's buffer ops come first, in each function, then
// each match's default binding named as its scrutinee, and the static
// lifetime of static data and what is read from it:
// reset/reuse and borrow inference decide by which use consumes a value, so
// they read the adopts and gives that placement then counts. Then
// reset/reuse (Reuses) decides where each dead box is taken apart and which
// cells go to recycling, and borrow inference (Borrows), which keeps every
// parameter a reuse takes apart owned, decides every parameter's grade.
// The grades go into every signature, and every body is placed under them
// in the same pass: a signature graded ahead of its callers' bodies breaks
// each call of it until they are placed, so no verifier may run between.
#include "idr/Analysis/Ownership.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/TypeGraph.h"
#include "idr/Transforms/Ownership.h"
#include "idr/Transforms/Pipeline.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/IR/Threading.h"

namespace idr {
#define GEN_PASS_DEF_IDRRCGRADES
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace {

struct Grades : idr::impl::IdrRcGradesBase<Grades> {
  void runOnProgram(idr::ProgramOp program) override {
    namespace own = idr::ownership;
    // Each function on its own, in parallel: its boundaries, then static
    // data graded at the static lifetime, which reuse, borrowing and
    // placement read off its type.
    SmallVector<idr::FuncOp> fns(program.getOps<idr::FuncOp>());
    parallelForEach(&getContext(), fns, [](idr::FuncOp fn) {
      own::boundaries(fn);
      own::rebindDefaults(fn);
      own::gradeStatic(fn);
    });
    const idr::Reuses &reuses = getAnalysis<idr::Reuses>();
    const SymbolTable &symbols = getAnalysis<SymbolTable>();
    const idr::Borrows &borrows = getAnalysis<idr::Borrows>();
    numBorrowed += borrows.borrowed();
    own::writeOwnedGrades(program, borrows);
    // Each body under the grades: the reuse rewrite at the sites decided,
    // then the counts, which read the function's own signature and its
    // callees'. No signature changes here, so the functions run in
    // parallel.
    parallelForEach(&getContext(), fns, [&](idr::FuncOp fn) {
      IRRewriter rewriter(fn.getContext());
      ArrayRef<idr::Reuses::Site> sites = reuses.sites(fn);
      own::reuseAt(rewriter, sites);
      numTakes += sites.size();
      for (const idr::Reuses::Site &site : sites)
        numReuses += site.cells.size();
      own::Counted reshaped = own::reshape(rewriter, fn, symbols);
      own::Counted placed = own::place(rewriter, fn, symbols);
      numDups += reshaped.dups + placed.dups;
      numDrops += reshaped.drops + placed.drops;
    });
    // The grades change no data type and no symbol.
    markAnalysesPreserved<SymbolTable, idr::TypeGraph, idr::Layouts>();
  }
};

} // namespace
