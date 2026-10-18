// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-rc-grades: the decisions counting takes on the program, and the owned
// grades they give every signature. The boundaries with upstream's buffer
// ops come first, in each function: reset/reuse and borrow inference decide
// by which use consumes a value, so they read the adopts and gives that
// placement then counts. An adopt gives an owned value, which a graded
// program holds, as this step leaves it: its signatures graded, its bodies
// counted only once placed. Then reset/reuse (Reuses) decides where each
// dead box is taken apart and which cells go to recycling, and borrow
// inference (Borrows), which keeps every parameter a reuse takes apart
// owned, decides every parameter's grade. The Reuses decided and the
// program's table stay in the program's analyses for idr-rc-place.
#include "idr/Analysis/Ownership.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/TypeGraph.h"
#include "idr/Transforms/Ownership.h"
#include "idr/Transforms/Pipeline.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
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
    // Each function on its own, in parallel.
    SmallVector<idr::FuncOp> fns(program.getOps<idr::FuncOp>());
    parallelForEach(&getContext(), fns, idr::ownership::boundaries);
    // Reset/reuse on the boundaries; borrow inference reads it, and so does
    // idr-rc-place, with the table, from the program's analyses.
    getAnalysis<idr::Reuses>();
    getAnalysis<SymbolTable>();
    const idr::Borrows &borrows = getAnalysis<idr::Borrows>();
    numBorrowed += borrows.borrowed();
    idr::ownership::writeOwnedGrades(program, borrows);
    // The grades change no data type, no symbol and no reuse decided.
    markAnalysesPreserved<idr::Reuses, SymbolTable, idr::TypeGraph, idr::Layouts>();
  }
};

} // namespace
