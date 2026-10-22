// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-in-place (idr/Transforms/InPlace.h): the in-place promise decided on
// the program as written (Rule.cpp), then refused here, or made into
// versions (Versions.cpp) and written (Writer.cpp).
//
// A refusal names the user's call: the first call whose argument cannot be
// shown to pay what its callee is owed, never a call inside a function that
// only passes its own parameter on (that parameter is owed in turn), with a
// note at the cause. The pass rewrites nothing unless every requirement
// holds.
#include "idr/Transforms/InPlace.h"

#include "idr/Transforms/InPlace/Rule.h"

#include "idr/Analysis/Ownership/Facts.h"
#include "idr/Analysis/Solver/ProgramGraph.h"
#include "idr/Analysis/Solver/Work.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Pipeline.h"

#include "mlir/IR/SymbolTable.h"
#include "llvm/ADT/STLExtras.h"

#include <array>

#define GEN_PASS_DEF_IDRINPLACE
#include "idr/IR/Generated/PassDialects.h.inc"

namespace idr {
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace {

using namespace idr::inplace;
using idr::solver::FunctionId;

// What a refusal's note says of its cause, by the cause's kind.
constexpr std::array<llvm::StringLiteral, 5> notes{
    "used again here, where the call may still hold it",
    "shared here",
    "made here, by an op that says nothing of what it holds",
    "given back here by a callee that may give it back shared",
    "given to the program from outside",
};
static_assert(static_cast<unsigned>(Why::FromOutside) + 1 == notes.size(),
              "a note per cause, in Why's order");

StringRef noteOf(Why why) { return notes[static_cast<unsigned>(why)]; }

// The family as the user wrote it: its declaration's label.
StringRef labelOf(idr::DataType family) {
  return family ? family.getGroup().label(family.getMember()).getValue() : StringRef("value");
}

// A refusal is a few handles, taken by value as MLIR passes ops: an op's
// accessors are not const, so a const handle could not name its function.
void report(Refusal refusal) {
  InFlightDiagnostic error = idr::refuse(refusal.at, idr::Rule::Uniqueness);
  StringRef family = labelOf(refusal.family);
  if (refusal.callee)
    error << refusal.caller.getSymName() << " passes a shared " << family << " to "
          << refusal.callee->getSymName() << ", which writes it in place";
  else
    error << refusal.caller.getSymName() << " rebuilds a shared " << family << " in place";
  error.attachNote(refusal.cause.at->getLoc()) << noteOf(refusal.cause.why);
}

struct InPlace : idr::impl::IdrInPlaceBase<InPlace> {
  void runOnProgram(idr::ProgramOp program) {
    idr::solver::ProgramGraph &graph = getAnalysis<idr::solver::ProgramGraph>();
    idr::solver::Work work;
    Keeps keeps = keepsOf(graph);
    Summaries summaries = summariesOf(graph, keeps, work);
    Verdict verdict = decide(graph, summaries, keeps);
    numWork += work.steps();
    if (!verdict.refusals.empty()) {
      for (const Refusal &refusal : verdict.refusals)
        report(refusal);
      return signalPassFailure();
    }
    // The verdict writes where a cell is rebuilt or a parameter is owed a
    // claim, which nothing before this pass writes.
    bool promised = llvm::any_of(graph.functions(), [&](FunctionId fn) {
      return !verdict.sites[fn].empty() ||
             llvm::any_of(verdict.obligations[fn],
                          [](std::optional<idr::ownership::Asks> owed) { return owed.has_value(); });
    });
    if (!promised) {
      markAllAnalysesPreserved();
      return;
    }
    Versions versions = versionsOf(graph, summaries, keeps, verdict);
    idr::solver::Work writing;
    LogicalResult written =
        writeVerdict(program, graph, versions, getAnalysis<SymbolTable>(), writing);
    numWork += writing.steps();
    if (failed(written))
      return signalPassFailure();
    markAnalysesPreserved<idr::solver::ProgramGraph, SymbolTable>();
  }
};

} // namespace
