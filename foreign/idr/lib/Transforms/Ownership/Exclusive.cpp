// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-rc-exclusive: the owned values that hold the only reference to every
// cell they reach, graded exclusive, on the program placement left. A value
// some view of which took a reference of its own is shared where it is
// consumed; the solve of the program then decides grade specialization's
// keys; the solve of the program with their copies, which sends each call
// where it gives, is the one the grades come from (with no copy the first
// is that solve too); each call goes where that solve sent it, the grades
// it proved go into every signature, and each function is committed,
// nested. The commit reads the solve, which no analysis of the program can
// be: it is made from the copies decided here, solved twice, and read after
// the calls moved.
#include "idr/Analysis/Ownership.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/TypeGraph.h"
#include "idr/Transforms/Ownership.h"
#include "idr/Transforms/Pipeline.h"

#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Pass/PassManager.h"

namespace idr {
#define GEN_PASS_DEF_IDRRCEXCLUSIVE
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace {

struct Exclusive : idr::impl::IdrRcExclusiveBase<Exclusive> {
  void runOnProgram(idr::ProgramOp program) override {
    namespace own = idr::ownership;
    SymbolTable &symbols = getAnalysis<SymbolTable>();
    own::shareTainted(program, symbols);
    idr::Exclusivity solved = idr::Exclusivity::solve(program, own::Copies());
    FailureOr<own::Copies> copies = own::specializeOnGrade(program, solved, symbols);
    if (failed(copies))
      return signalPassFailure();
    if (!copies->of.empty()) {
      solved = idr::Exclusivity::solve(program, *copies);
      own::redirectCalls(program, solved);
    }
    own::writeExclusiveGrades(program, solved, symbols);

    // Every function in parallel, while the solve and the table, which
    // the commit only reads, live here.
    OpPassManager nested(idr::ProgramOp::getOperationName());
    nested.addNestedPass<idr::FuncOp>(own::createRcCommit(solved, symbols, numExclusive));
    if (failed(runPipeline(nested, program)))
      return signalPassFailure();
    // No data type changed, and every symbol came through the table.
    markAnalysesPreserved<idr::TypeGraph, idr::Layouts, SymbolTable>();
  }
};

} // namespace
