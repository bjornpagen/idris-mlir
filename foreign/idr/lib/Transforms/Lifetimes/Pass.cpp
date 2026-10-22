// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-lifetimes: the decide step. Every lifetime is born decided: this step
// writes each opener, its kind, the slots and cells stated in it, the calls
// that put into it, every copy of a function by the kind of lifetime it is
// given and that copy's signature, at once, so no lifetime is ever
// undecided in the IR.
//
// A cell idr.cell.new makes in counted memory is made in a lifetime
// instead, as upstream's promote-buffers-to-stack makes a memref.alloc a
// memref.alloca, when nothing its box reaches must be counted. A value must
// be counted when it goes where no lifetime of the function follows it (it
// is returned, passed to a call, stored into memory that outlives it,
// carried into the next run of a region that runs again), when nothing can
// state where it lives (a parameter, a counted call's result, a value of an
// op with no lifetime operand), and when it is made of such a value or
// made into one: a cell of a lifetime holds no counted field, since a
// lifetime's end frees its memory and drops nothing, and a value merging a
// counted one with a cell of a lifetime would have no one grade. So the
// values that must be counted are everything the flow graph links to those,
// whichever way the link goes: one marking over the function's values,
// never a set per value and never the whole program's graph.
//
// A call puts into a lifetime of its caller what its callee's copy for that
// lifetime's kind gives: a copy is its owner with one more parameter, the
// lifetime, into which it puts each cell whose box reaches only what it
// returns, those results living there. A copy for a room puts a bounded
// amount (each cell once, each callee's copy a room's); one for a cursor or
// a home takes every value it makes there into what it gives back on every
// path, so a caller's lifetime keeps no garbage of it. Each function is
// decided callees first, a component of the call graph from the most every
// member's copy could put, shrinking until none does; then its own body,
// where each call whose results nothing counted reaches is the copy's.
//
// A run (the function's body, or a region that runs again) gets one
// lifetime for its cells and calls: this activation when only slots are
// stated in it and no call of the function continues on a frame; an opener
// with no memory around the ops that use it when only slots are; a block of
// the frame when every call puts a bounded amount; the shard's home when
// the run is the root's body; a cursor otherwise, on the stack of the
// cursor around it where there is one, else its own chain. A lifetime that
// spans a call continuing on a frame is a cursor's, its cells bumped there,
// never slots or a block, which cannot move into a frame. A cursor's or a
// home's calls stand at the top of its region, and each value one gives is
// used again after every allocation that follows it. A run whose lifetime
// would hold a call in tail position, or a jump out of it, keeps its cells
// counted. What the lifetime holds is then graded `scoped`, and the op that
// makes each such value states the lifetime.
#include "idr/Transforms/Lifetimes/Plan.h"

#include "idr/IR/Grades.h"
#include "idr/Transforms/Effects.h"
#include "idr/Transforms/Lifetimes.h"
#include "idr/Transforms/Pipeline.h"

#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/SymbolTable.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <array>
#include <optional>
#include <tuple>
#include <utility>

namespace idr {
#define GEN_PASS_DEF_IDRLIFETIMES
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;
using namespace idr;
using namespace idr::lifetimes::decide;

namespace {

// The most a function's copies could put: every result that holds a
// reference, for every kind. The root's results hold no runtime value.
std::optional<Copies> mostOf(FuncOp fn) {
  if (fn.isRoot())
    return std::nullopt;
  Copies most{CopyModes::all(), {}};
  for (auto [index, type] : llvm::enumerate(fn.getResultTypes()))
    if (holdsLiving(type))
      most.results.push_back(static_cast<unsigned>(index));
  return most.results.empty() ? std::nullopt : std::optional(most);
}

std::optional<Copies> copiesOf(const Plan &plan) {
  if (!plan.put)
    return std::nullopt;
  return Copies{plan.put->modes, plan.put->results};
}

struct IdrLifetimes : impl::IdrLifetimesBase<IdrLifetimes> {
  void runOnProgram(ProgramOp program) {
    SymbolTable &symbols = getAnalysis<SymbolTable>();
    solver::ProgramGraph &graph = getAnalysis<solver::ProgramGraph>();
    solver::Work work;

    // Callees first: a component's copies start at the most each member's
    // could put and shrink to what each member's plan puts, given the
    // others', until none shrinks; each round shrinks one at least, so it
    // ends. Then each member's own body.
    IndexVector<FunctionId, std::optional<Copies>> copies = graph.table(std::optional<Copies>{});
    IndexVector<FunctionId, Plan> copyPlans = graph.table(Plan{});
    IndexVector<FunctionId, Plan> ownPlans = graph.table(Plan{});
    for (solver::SccId component : graph.sccCount().ids()) {
      auto members = graph.members(component);
      for (FunctionId f : members)
        copies[f] = mostOf(graph.op(f));
      for (bool shrank = true; shrank;) {
        shrank = false;
        for (FunctionId f : members)
          if (copies[f])
            copyPlans[f] = Planner(graph.op(f), f, graph, copies, Reading::Put, work).plan();
        for (FunctionId f : members)
          if (copies[f]) {
            std::optional<Copies> now = copiesOf(copyPlans[f]);
            if (now != copies[f]) {
              copies[f] = std::move(now);
              shrank = true;
            }
          }
      }
      for (FunctionId f : members)
        ownPlans[f] = Planner(graph.op(f), f, graph, copies, Reading::Counted, work).plan();
    }

    // The copies the program calls: those its functions' runs call, and
    // those each copy calls in turn, of its own runs' kinds and, for what it
    // puts into its parameter, of its own kind.
    IndexVector<FunctionId, CopyModes> wanted = graph.table(CopyModes::none());
    footprint::Vector<std::pair<FunctionId, CopyMode>> pending;
    auto want = [&](FunctionId f, CopyMode mode) {
      if (!wanted[f].contains(mode)) {
        wanted[f] = wanted[f].with(mode);
        pending.emplace_back(f, mode);
      }
    };
    auto wantRuns = [&](const Plan &plan) {
      for (const Group &group : plan.groups)
        for (const PutCall &call : group.calls)
          want(call.callee, modeOf(group.source));
    };
    for (FunctionId f : graph.functions())
      wantRuns(ownPlans[f]);
    while (!pending.empty()) {
      auto [f, mode] = pending.back();
      pending.pop_back();
      wantRuns(copyPlans[f]);
      for (const PutCall &call : copyPlans[f].put->calls)
        want(call.callee, mode);
    }

    // Each copy made from its owner as the plans read it, before anything
    // is written; then every copy written, then every owner.
    IndexVector<FunctionId, std::array<FuncOp, 3>> made = graph.table(std::array<FuncOp, 3>{});
    footprint::Vector<std::tuple<FunctionId, CopyMode, FuncOp>> written;
    MLIRContext *ctx = program.getContext();
    for (FunctionId f : graph.functions())
      for (CopyMode mode : everyMode) {
        if (!wanted[f].contains(mode))
          continue;
        FuncOp owner = graph.op(f);
        SmallVector<Type, 4> inputs(owner.getArgumentTypes());
        inputs.push_back(LifetimeType::get(ctx, kindOf(mode)));
        SmallVector<Type, 2> results(owner.getResultTypes());
        for (unsigned result : copies[f]->results)
          results[result] = scopedType(results[result]);
        ModeKey key{f, FunctionType::get(ctx, inputs, results)};
        FailureOr<FuncOp> copy = specialize::makeCopy<Modes>(
            owner, key, specialize::nameOf<Modes>(owner.getSymNameAttr(), key));
        if (failed(copy)) {
          owner.emitOpError("internal error: idr-lifetimes could not make a copy of it");
          return signalPassFailure();
        }
        symbols.insert(*copy, std::next(owner->getIterator()));
        made[f][static_cast<unsigned>(mode)] = *copy;
        written.emplace_back(f, mode, *copy);
      }

    Writer writer(made);
    for (auto [f, mode, copy] : written)
      numLifetimes += writer.write(copy, copyPlans[f],
                                   std::pair(copy.getArgument(copy.getNumArguments() - 1), mode));
    footprint::Vector<std::pair<FunctionId, FuncOp>> edited;
    for (FunctionId f : graph.functions()) {
      const Plan &plan = ownPlans[f];
      if (plan.groups.empty())
        continue;
      numLifetimes += writer.write(graph.op(f), plan, std::nullopt);
      if (llvm::any_of(plan.groups, [](const Group &group) { return !group.calls.empty(); }))
        edited.emplace_back(f, graph.op(f));
    }
    bool wrote = !written.empty() ||
                 llvm::any_of(graph.functions(), [&](FunctionId f) { return !ownPlans[f].groups.empty(); });
    if (!wrote) {
      numWork = work.steps();
      return markAllAnalysesPreserved();
    }

    // The copies join the program graph, every function whose calls changed
    // and every copy with the row its calls now make; then the one writer of
    // rows, since a slot is no heap memory and a copy's row is its own.
    {
      solver::Editor editor = graph.thaw();
      for (auto [f, mode, copy] : written)
        edited.emplace_back(editor.insert(copy), copy);
      for (auto [id, fn] : edited)
        editor.setCallees(id, solver::rowOf(fn, editor));
      std::move(editor).freeze();
    }
    rows::write(program, graph, work);
    numWork = work.steps();
    markAnalysesPreserved<SymbolTable, solver::ProgramGraph>();
  }
};

} // namespace
