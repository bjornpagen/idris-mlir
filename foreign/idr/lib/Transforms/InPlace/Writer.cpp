// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The in-place verdict written (Rule.h, writeVerdict): the versions it makes
// of each function (Versions.cpp) as types and ops. Each grade copy is made
// by the specializer's one clone-and-key template, keyed by the results it
// gives and the parameters it is owed; every version's values are graded
// with their claims, its parameters with what they are owed, and each call
// goes to the version of its callee it asks for. Each rebuild site becomes
// a take of the cell at its case's entry, whose fields the case's reads
// become, and an idr.token.rebuild that consumes its linear token in place
// of the construction paired with it. The local rule then carries every
// claim written forward into what each value is taken or read into at a
// linear position, and where a value graded with a claim meets a position
// that takes less (an op of upstream's among them, which takes the bare
// carrier), it is shared into it.
#include "idr/Transforms/InPlace/Rule.h"

#include "idr/Analysis/Ownership/Facts.h"
#include "idr/Analysis/Ownership/GradeCopies.h"
#include "idr/Analysis/Ownership/Meets.h"
#include "idr/Analysis/Solver/ProgramGraph.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Effects.h"
#include "idr/Transforms/InPlace/Unique.h"
#include "idr/Transforms/Lifetimes/Lend.h"

#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/SymbolTable.h"
#include "llvm/ADT/STLExtras.h"

#include <utility>

using namespace mlir;

namespace idr::inplace {

namespace {

// The key of a version of `fn`: per parameter the claim it is owed, per
// result the claim it gives back, the original's claim where it asks none.
ownership::PromiseCopies::Key keyOf(FunctionId owner, FuncOp fn, const Version &version) {
  ownership::PromiseCopies::Key key{owner, {}, {}};
  for (auto [param, type] : llvm::enumerate(fn.getArgumentTypes()))
    key.params.push_back(version.params[param] ? ownership::claimFor(*version.params[param])
                                               : ownership::claimOf(type));
  for (auto [result, type] : llvm::enumerate(fn.getResultTypes()))
    key.results.push_back(version.results[result] ? ownership::claimFor(*version.results[result])
                                                  : ownership::claimOf(type));
  return key;
}

// `type` raised to the claim `asks`, where its sharing is still open below
// it.
Type claimed(Type type, Asks asks) {
  Unique claim = ownership::claimFor(asks);
  return ownership::leavesOpen(type, claim) ? ownership::claiming(type, claim) : type;
}

// A version's values graded, its parameters with what they are owed, its
// signature with them.
void grade(FuncOp op, const Version &version) {
  Walk walk(op);
  for (auto [value, asks] : llvm::zip_equal(walk.values, version.grades))
    if (asks)
      value.setType(claimed(value.getType(), *asks));
  for (auto [param, asks] : llvm::zip_equal(op.getBody().front().getArguments(), version.params))
    if (asks)
      param.setType(claimed(param.getType(), *asks));
  SmallVector<Type> results(op.getResultTypes());
  for (auto [type, asks] : llvm::zip_equal(results, version.results))
    if (asks)
      type = claimed(type, *asks);
  op.setFunctionType(FunctionType::get(
      op.getContext(), llvm::to_vector(op.getBody().front().getArgumentTypes()), results));
}

// Each rebuild site of a version whose walk is `walk`, rewritten: the
// argument its case binds names the match and the case.
void rewriteSites(llvm::ArrayRef<SiteAt> sites, const Walk &walk) {
  for (const SiteAt &site : sites) {
    auto taken = cast<BlockArgument>(walk.values[site.taken]);
    rebuild(cast<DataMatchOp>(taken.getOwner()->getParentOp()),
            taken.getOwner()->getParent()->getRegionNumber(), taken.getArgNumber(),
            cast<DataConOp>(walk.values[site.construction].getDefiningOp()));
  }
}

} // namespace

LogicalResult writeVerdict(ProgramOp program, solver::ProgramGraph &graph,
                           const Versions &versions, SymbolTable &symbols, solver::Work &work) {
  // The copies, cloned from their originals before any original changes,
  // each right after its original.
  IndexVector<FunctionId, SmallVector<FuncOp, 1>> ops = graph.table<SmallVector<FuncOp, 1>>();
  SmallVector<FunctionId> functions(graph.functions().begin(), graph.functions().end());
  for (FunctionId fn : functions) {
    FuncOp original = graph.op(fn);
    ops[fn].push_back(original);
    for (const Version &version : llvm::drop_begin(versions.of[fn])) {
      FailureOr<FuncOp> copy = ownership::gradeCopy<ownership::PromiseCopies>(
          original, keyOf(fn, original, version), symbols);
      if (failed(copy))
        return failure();
      ops[fn].push_back(*copy);
    }
  }
  // Every version graded before any call reads a callee's signature.
  for (FunctionId fn : functions)
    for (auto [version, op] : llvm::zip(versions.of[fn], ops[fn]))
      grade(op, version);
  // Each call to the version it asks for; then the results of every call
  // of a function whose signature changed are its callee's again, and
  // every position of a function that changed or calls one is met.
  BitSet<FunctionId> touched(graph.size());
  for (FunctionId fn : functions)
    for (auto [version, op] : llvm::zip(versions.of[fn], ops[fn])) {
      (void)touched.raise(fn);
      for (FunctionId caller : graph.callers(fn))
        (void)touched.raise(caller);
      Walk walk(op);
      for (auto [index, call] : llvm::enumerate(walk.calls))
        if (!version.demands[index].empty()) {
          FunctionId callee = graph.id(call.getCalleeAttr());
          call.setCalleeAttr(
              FlatSymbolRefAttr::get(ops[callee][version.targets[index]].getSymNameAttr()));
        }
      rewriteSites(versions.sites[fn], walk);
    }
  auto calleeOf = [&](CallOp call) {
    return symbols.lookup<FuncOp>(call.getCalleeAttr().getAttr());
  };
  for (FunctionId fn : functions)
    if (touched.test(fn))
      for (FuncOp op : ops[fn])
        op.walk([&](CallOp call) { call.copyCallee(calleeOf(call)); });
  // The copies join the program graph, every version's row what its calls
  // now name. Each version's id is kept, in the order of `ops`: the
  // original's own, then each copy's as the editor gives it.
  IndexVector<FunctionId, SmallVector<FunctionId, 1>> ids =
      graph.table<SmallVector<FunctionId, 1>>();
  for (FunctionId fn : functions)
    ids[fn].push_back(fn);
  solver::Editor editor = graph.thaw();
  SmallVector<std::pair<FunctionId, FuncOp>> edited;
  for (FunctionId fn : functions) {
    if (versions.of[fn].empty())
      continue;
    edited.emplace_back(fn, ops[fn].front());
    for (FuncOp copy : llvm::drop_begin(ops[fn])) {
      FunctionId id = editor.insert(copy);
      ids[fn].push_back(id);
      edited.emplace_back(id, copy);
    }
  }
  for (auto [id, op] : edited)
    editor.setCallees(id, solver::rowOf(op, editor));
  std::move(editor).freeze();
  // The claims written here carried forward by the local rule, before any
  // position is met, so no share stands where a claim flows on: a parameter
  // graded at the boundary reaches what its body takes or reads it into at
  // a linear position, the buffer its cell holds among them, which
  // bufferization reads. Then every position the verdict changed is met,
  // each holder now graded past the bare carrier lent to the ops of
  // upstream's that read it, and every row is its derivation again.
  (void)unique::raiseClaims(graph, *program.getContext(), work);
  for (FunctionId fn : functions)
    if (touched.test(fn))
      for (auto [op, id] : llvm::zip_equal(ops[fn], ids[fn])) {
        ownership::shareIntoPositions(op, calleeOf);
        (void)lifetimes::lendReads(op, id, graph, lifetimes::Holders::Graded);
      }
  rows::write(program, graph, work);
  return success();
}

} // namespace idr::inplace
