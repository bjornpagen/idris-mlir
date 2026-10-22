// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-rc-exclusive: exclusivity, solved once by context (the Exclusivity
// analysis), written into the types by this step and by no other. Each
// version of a function the solve kept beyond the general one becomes a
// grade copy, made by the specializer's one clone-and-key template right
// after its original; then every version's values the solve proved
// exclusive are graded `unique deep`, its signature with them, each call
// goes to the version of its callee the solve sent it to, and wherever an
// exclusive value meets a position that takes less (a call of the general
// version, a result some return leaves shared, a region input another
// predecessor shares), it is shared into it. Every type is made here, in
// the program's order, and the program graph is edited through its one
// editor; the answer then lives in the types, which every later pass keeps
// and the verifier checks, so no step reads the solve again.
#include "idr/Analysis/Ownership.h"

#include "idr/Analysis/Ownership/Facts.h"
#include "idr/Analysis/Ownership/GradeCopies.h"
#include "idr/Analysis/Ownership/Meets.h"
#include "idr/Analysis/Ownership/Walks.h"
#include "idr/Analysis/Solver/ProgramGraph.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/TypeGraph.h"
#include "idr/Transforms/Effects.h"
#include "idr/Transforms/Pipeline.h"

#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/SymbolTable.h"
#include "llvm/ADT/STLExtras.h"

#include <tuple>

namespace idr {
#define GEN_PASS_DEF_IDRRCEXCLUSIVE
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace {

using idr::Exclusivity;
using idr::solver::FunctionId;

// The key of version `version` of `fn`: `unique deep` at each parameter it
// takes exclusive and each result it gives exclusive, the original's claim
// elsewhere.
idr::ownership::ContextCopies::Key keyOf(FunctionId owner, idr::FuncOp fn,
                                       const Exclusivity::Version &version) {
  idr::ownership::ContextCopies::Key key{owner, {}, {}};
  for (auto [index, type] : llvm::enumerate(fn.getArgumentTypes()))
    key.params.push_back(version.key.test(static_cast<unsigned>(index))
                             ? idr::Unique::Deep
                             : idr::ownership::claimOf(type));
  for (auto [index, type] : llvm::enumerate(fn.getResultTypes()))
    key.results.push_back(version.results.test(static_cast<unsigned>(index))
                              ? idr::Unique::Deep
                              : idr::ownership::claimOf(type));
  return key;
}

// `version`'s exclusive values of `fn` graded `unique deep`, and its
// signature with them: its entry arguments and its exclusive results. The
// followed values are read whole before any is graded, since grading one
// takes it out of what the walk follows. Returns how many it graded.
unsigned writeVersion(idr::FuncOp fn, const Exclusivity::Version &version) {
  SmallVector<Value> values;
  idr::exclusivity::forEachFollowed(fn, [&](Value value, std::uint32_t) { values.push_back(value); });
  unsigned graded = 0;
  for (auto [local, value] : llvm::enumerate(values))
    if (version.exclusive.test(static_cast<unsigned>(local))) {
      value.setType(idr::ownership::claiming(value.getType(), idr::Unique::Deep));
      ++graded;
    }
  SmallVector<Type> results(fn.getResultTypes());
  for (auto [index, type] : llvm::enumerate(results))
    if (version.results.test(static_cast<unsigned>(index)) &&
        idr::ownership::leavesOpen(type, idr::Unique::Deep))
      type = idr::ownership::claiming(type, idr::Unique::Deep);
  fn.setFunctionType(FunctionType::get(
      fn.getContext(), llvm::to_vector(fn.getBody().front().getArgumentTypes()), results));
  return graded;
}

// `fn`'s row of the program graph: each distinct (callee, tail kind) once,
// with how many of its calls have it, as the graph keeps rows.
SmallVector<idr::solver::Call> rowOf(idr::FuncOp fn, const idr::solver::Editor &editor) {
  SmallVector<idr::solver::Call> row;
  fn.getBody().walk([&](idr::CallOp call) {
    row.push_back({editor.id(call.getCalleeAttr()), call.getTailKind(), 1});
  });
  llvm::sort(row, [](const idr::solver::Call &a, const idr::solver::Call &b) {
    return std::tuple(a.callee.index(), a.kind) < std::tuple(b.callee.index(), b.kind);
  });
  SmallVector<idr::solver::Call> merged;
  for (const idr::solver::Call &call : row)
    if (!merged.empty() && merged.back().callee == call.callee && merged.back().kind == call.kind)
      ++merged.back().sites;
    else
      merged.push_back(call);
  return merged;
}

struct Exclusive : idr::impl::IdrRcExclusiveBase<Exclusive> {
  void runOnProgram(idr::ProgramOp program) override {
    const Exclusivity &solved = getAnalysis<Exclusivity>();
    if (solved.brokeInvariant())
      return signalPassFailure();
    idr::solver::ProgramGraph &graph = getAnalysis<idr::solver::ProgramGraph>();
    SymbolTable &symbols = getAnalysis<SymbolTable>();

    // Each function's versions, the original first, each copy right after
    // it, read off the frozen graph before it is thawed.
    idr::IndexVector<FunctionId, SmallVector<idr::FuncOp, 1>> versionOps =
        graph.table<SmallVector<idr::FuncOp, 1>>();
    SmallVector<FunctionId> functions(graph.functions().begin(), graph.functions().end());
    for (FunctionId fn : functions) {
      idr::FuncOp original = graph.op(fn);
      versionOps[fn].push_back(original);
      for (const Exclusivity::Version &version : llvm::drop_begin(solved.versions(fn))) {
        FailureOr<idr::FuncOp> copy = idr::ownership::gradeCopy<idr::ownership::ContextCopies>(
            original, keyOf(fn, original, version), symbols);
        if (failed(copy))
          return signalPassFailure();
        versionOps[fn].push_back(*copy);
      }
    }

    // Every version's values and signature, before any call reads a
    // callee's.
    for (FunctionId fn : functions)
      for (auto [version, op] : llvm::zip_equal(solved.versions(fn), versionOps[fn]))
        numExclusive += writeVersion(op, version);

    // Every call to the version the solve sent it to, with its results
    // that version's; then every position met.
    for (FunctionId fn : functions)
      for (auto [version, op] : llvm::zip_equal(solved.versions(fn), versionOps[fn])) {
        unsigned site = 0;
        idr::ownership::forEachCall(op, [&](idr::CallOp call) {
          FunctionId callee = graph.id(call.getCalleeAttr());
          idr::FuncOp target = versionOps[callee][version.callTargets[site++]];
          call.setCalleeAttr(FlatSymbolRefAttr::get(target.getSymNameAttr()));
          for (auto [result, type] : llvm::zip_equal(call->getResults(), target.getResultTypes()))
            result.setType(type);
        });
        idr::ownership::shareIntoPositions(op, [&](idr::CallOp call) {
          return symbols.lookup<idr::FuncOp>(call.getCalleeAttr().getAttr());
        });
      }

    // The copies join the program graph, and every version's row is what
    // its calls now name.
    idr::solver::Editor editor = graph.thaw();
    SmallVector<std::pair<FunctionId, idr::FuncOp>> edited;
    for (FunctionId fn : functions) {
      edited.emplace_back(fn, versionOps[fn].front());
      for (idr::FuncOp copy : llvm::drop_begin(versionOps[fn]))
        edited.emplace_back(editor.insert(copy), copy);
    }
    for (auto [id, op] : edited)
      editor.setCallees(id, rowOf(op, editor));
    std::move(editor).freeze();
    // A parameter now exclusive may carry a write of its own, and a copy's
    // calls are its version's: the one writer of rows makes every row its
    // derivation again.
    idr::rows::write(program, graph);

    numContexts += solved.contexts();
    numCopies += solved.copies();
    numRounds += solved.rounds();
    // No data type changed, every symbol came through the table, and the
    // program graph was edited where the calls moved.
    markAnalysesPreserved<idr::TypeGraph, idr::Layouts, SymbolTable, idr::solver::ProgramGraph>();
  }
};

} // namespace
