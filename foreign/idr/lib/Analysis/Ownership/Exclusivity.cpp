// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Exclusivity: which owned values hold the only reference to every cell
// of their cell graph that a take could hand out, so that taking them
// apart needs no count test, and building in their cells no null test.
// Those are the cells with fields; static data built only of atoms has
// none to hand out (an atom has no fields to take, an unboxed sum no
// cell), no count reaches it and nothing frees or writes it, so it is in
// every exclusive tree however many hold it (reachesOnlyAtoms).
//
// In the owned stage a reference is duplicated only by idr.dup, so
// exclusivity is provenance, read from the reference edges of each op
// (idr/IR/Flow.h): a value is exclusive when its op makes it new and every
// cell moved into a part of it is exclusive (a constructor of exclusive
// fields), when a use of an exclusive value moves into it whole or out of
// one of its parts (a change of quantity; a field an exclusive value was
// taken apart into, and the token of that take), when it is a call's
// result that every return makes exclusive or a parameter every caller
// passes exclusive, or when it is a copy of static data built only of
// atoms. So the pair of empty lists that span and splitAt give at the end
// of their input joins the pair they build around an exclusive one, and
// the join stays exclusive. Any other copy, a constant, a stack cell (the
// frame's, so not new to anyone), a value no flow explains (a share's,
// which forgets what its operand alone reached) and a value from a caller
// the program does not show are shared, and so is every result of an op
// that declares no flow. The analysis is a sparse forward dataflow on
// MLIR's solver, optimistic as SCCP is: a value is exclusive until a path
// shares it, which is sound by induction on the run. It reads the dups
// placement made, so it runs after placement; what it proves idr-rc writes
// into the types (`!idr.excl<T>`), which every later pass keeps and the
// owned stage's verifier checks.
//
// It is context-sensitive where grade specialization made a context: a
// call of a key or of its copy runs, within the solve, the copy when every
// value it passes at a followed parameter is exclusive and the original
// otherwise, and only the functions some call that runs goes to run
// (ExclusivityAnalyses.cpp). The solve is that of the program after each
// call went where the solve found it goes, and may be less precise than
// one solved afresh, never unsound.
//
// The solver answers by program point and value, which the passes after
// it ask of the function they rewrite; so this unit runs it and copies its
// answers into tables, and the solver is gone when the solve returns.
#include "idr/Analysis/Ownership/ExclusivityDetail.h"

#include "idr/Analysis/Ownership.h"
#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Worklist.h"

#include "mlir/Analysis/DataFlow/DeadCodeAnalysis.h"
#include "mlir/Analysis/DataFlowFramework.h"
#include "llvm/ADT/STLExtras.h"

#include <variant>

using namespace mlir;
using namespace mlir::dataflow;

namespace idr {

namespace exclusivity = detail::exclusivity;
using exclusivity::CellsLattice;
using exclusivity::exclusive;
using Sharing = Exclusivity::Sharing;

FailureOr<Exclusivity> Exclusivity::solve(ProgramOp program, const ownership::Copies &copies) {
  exclusivity::Calls calls(program, copies);
  DataFlowSolver solver(DataFlowConfig().setInterprocedural(true));
  exclusivity::loadAnalyses(solver, program, calls);
  if (mlir::failed(solver.initializeAndRun(program)))
    return failure();

  Exclusivity out;
  auto record = [&](Value value) {
    if (auto *lattice = solver.lookupState<CellsLattice>(value);
        lattice && lattice->getValue().sharing != Sharing::Unknown)
      out.sharing[value] = lattice->getValue().sharing;
  };
  // A value the solve never reached is unknown, which counts as exclusive.
  auto passesExclusive = [&](Value arg) {
    const CellsLattice *lattice = solver.lookupState<CellsLattice>(arg);
    return !lattice || exclusive(*lattice);
  };
  auto executable = [&](Block *block) {
    const Executable *state = solver.lookupState<Executable>(solver.getProgramPointBefore(block));
    return state && state->isLive();
  };
  // The functions that run once each call goes where the solve finally sent
  // it: those whose callers the program does not all show, and each a live
  // call of one goes to, each function once. A copy a call went to before
  // an argument of it was found shared, and none went to after, the solve
  // ran (a function only ever starts to run) but the program never does:
  // nothing of it is live, and none of its calls is any function's caller.
  OnceWorklist<FuncOp> reached;
  for (FuncOp fn : program.getOps<FuncOp>())
    if (const auto *callers = solver.lookupState<PredecessorState>(solver.getProgramPointAfter(fn));
        callers && !callers->allPredecessorsKnown())
      (void)reached.push(fn);
  // The calls that run, by the function each runs.
  DenseMap<Operation *, SmallVector<Operation *>> runsFrom;
  while (std::optional<FuncOp> fn = reached.pop())
    fn->walk([&](Block *block) {
      if (!executable(block))
        return;
      out.liveBlocks.insert(block);
      for (CallOp call : block->getOps<CallOp>()) {
        FuncOp target = calls.target(call, passesExclusive);
        if (std::holds_alternative<exclusivity::Calls::Pair>(calls.calleeOf(call)))
          out.targets.try_emplace(call, target);
        runsFrom[target].push_back(call);
        (void)reached.push(target);
      }
    });
  program.walk([&](Block *block) {
    for (BlockArgument arg : block->getArguments())
      record(arg);
    for (Operation &inner : *block)
      for (Value result : inner.getResults())
        record(result);
  });
  for (FuncOp fn : program.getOps<FuncOp>()) {
    auto from = runsFrom.find(fn);
    if (llvm::all_of(calls.namesOf(fn), [&](FuncOp named) {
          const auto *callers =
              solver.lookupState<PredecessorState>(solver.getProgramPointAfter(named));
          return callers && callers->allPredecessorsKnown();
        }))
      out.callersOf[fn] = from == runsFrom.end() ? SmallVector<Operation *>() : from->second;
    if (from == runsFrom.end())
      continue;
    SmallVector<Operation *> &returns = out.returnsOf[fn];
    for (ReturnOp ret : calls.returns(fn))
      if (out.liveBlocks.contains(ret->getBlock()))
        returns.push_back(ret);
  }
  return out;
}

Sharing Exclusivity::of(Value value) const {
  auto it = sharing.find(value);
  return it == sharing.end() ? Sharing::Unknown : it->second;
}

// A value its op moves one of its uses into whole, at the use's carrier
// (a change of quantity), is that use's value, and is proved as that is,
// solved or made after the solve. A share's value is reached whole by
// nothing, so the solve found it shared.
bool Exclusivity::proves(Value value) const {
  if (!ownership::followed(value))
    return false;
  if (auto flow = dyn_cast_or_null<FlowOpInterface>(value.getDefiningOp())) {
    FlowEdges edges;
    flow.getFlowEdges(edges);
    for (const FlowEdges::Edge &edge : edges.edges()) {
      const auto *move = std::get_if<FlowEdges::Flow>(&edge.move);
      if (!move || !edge.carries(Carrier::Reference))
        continue;
      const auto *use = std::get_if<FlowPoint::Taken>(&move->from.at);
      if (use && move->to == FlowPoint::of(value) &&
          unrestricted(use->use->get().getType()) == unrestricted(value.getType()))
        return proves(use->use->get());
    }
  }
  return of(value) == Sharing::Exclusive;
}

std::optional<FuncOp> Exclusivity::target(CallOp call) const {
  auto it = targets.find(call);
  if (it == targets.end())
    return std::nullopt;
  return it->second;
}

std::optional<ArrayRef<Operation *>> Exclusivity::callers(FuncOp fn) const {
  auto it = callersOf.find(fn);
  if (it == callersOf.end())
    return std::nullopt;
  return ArrayRef<Operation *>(it->second);
}

std::optional<ArrayRef<Operation *>> Exclusivity::returns(FuncOp fn) const {
  auto it = returnsOf.find(fn);
  if (it == returnsOf.end())
    return std::nullopt;
  return ArrayRef<Operation *>(it->second);
}

} // namespace idr
