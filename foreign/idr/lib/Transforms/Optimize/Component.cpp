// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// One component's turn in a wave, on a worker. A turn reads its own
// members, the functions final before the wave and nothing else, and
// writes its own members alone: every component of a wave is another, so
// the turns run in parallel and each is a function of what it reads.
//
// The members a turn takes up get their binding times; then each member
// runs its loop: a round of its inner pipeline, and another while the round
// asked for copies, once each copy is final, or inlined a leaf. A batch
// holding a copy that is not final parks the member until the wave ends,
// since only then is the copy in the program and taken up.
//
// The loop ends by construction: a member is given finitely many copies,
// each once, so the rounds that ask for one are finitely many, and a round
// that inlines a leaf grows the member, which the caller cap bounds. A
// round that only simplified ends the loop: what it exposed and no later
// round reads leaves the program less optimized, never different.
//
// When every member is done, the component becomes final between waves,
// where its facts are read off its final bodies: its unread parameters
// dropped first, then its rows and what each member gives back.

#include "idr/Transforms/OptimizeScheduler.h"

#include "idr/Analysis/BindingTimes.h"
#include "idr/Analysis/Identities.h"
#include "idr/IR/Effects.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Profile.h"
#include "idr/Transforms/EGraph.h"
#include "idr/Transforms/Inline.h"

#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::optimize {

Scheduler::Scheduler(OptimizePass &pass, Schedule &schedule, specialize::Nodes &nodes,
                     const InnerCounts &counts, AnalysisManager am, Admission &admission)
    : pass(pass), schedule(schedule), nodes(nodes), counts(counts), am(am), admission(admission),
      inner(FuncOp::getOperationName()) {
  buildInnerPipeline(inner, schedule, nodes, counts);
}

// A round: each call of a final callee says what its callee may now do,
// so the e-graph deletes and floats it by the callee's final row; then the
// pipeline, entered as the member's arena admits.
LogicalResult Scheduler::round(FunctionId member) {
  FuncOp fn = schedule.function(member);
  fn.getBody().walk([&](CallOp call) {
    if (std::optional<FunctionId> callee = schedule.find(call.getCalleeAttr()))
      if (std::optional<Readable> known = schedule.final(*callee))
        call.setRow(known->fn.getRow());
  });
  OpPassManager *pm = nullptr;
  {
    std::lock_guard lock(pipelinesMutex);
    if (idle.empty()) {
      pipelines.push_back(std::make_unique<OpPassManager>(inner));
      idle.push_back(pipelines.back().get());
    }
    pm = idle.pop_back_val();
  }
  std::uint64_t arena = egraph::arenaBytes(static_cast<std::uint64_t>(inlining::bodyOf(fn).size));
  admission.enter(arena);
  LogicalResult result = runNested(pass, *pm, fn);
  admission.leave(arena);
  std::lock_guard lock(pipelinesMutex);
  idle.push_back(pm);
  return result;
}

// The schedule gives each copy to one claimant, which builds it detached:
// the build reads only its owner, final or of the claimant's own component,
// and its body is a function of its key and its owner, whichever turn
// builds it.
LogicalResult Scheduler::build(ArrayRef<specialize::Node *> asked, FunctionId claimant,
                               Turn &turn) {
  for (specialize::Node *made : asked) {
    if (!nodes.claim(*made))
      continue;
    if (failed(nodes.build(*made, claimant)))
      return failure();
    turn.built.push_back(made);
  }
  return success();
}

// A member whose batch holds a copy that is neither final nor of its own
// component parks on the batch's first copy, keeping what its turn solved.
FailureOr<Outcome> Scheduler::parks(FunctionId member, SmallVector<specialize::Node *> asked,
                                    Turn &turn) {
  if (failed(build(asked, member, turn)))
    return failure();
  auto ready = [&](const specialize::Node *made) {
    return idr::match(
        made->phase,
        [&](const specialize::Placed &placed) {
          return schedule.final(placed.id).has_value() || schedule.sameComponent(placed.id, member);
        },
        [](const auto &) { return false; });
  };
  if (llvm::all_of(asked, ready))
    return Outcome::Continues;
  Schedule::Member &state = schedule.members[member.index()];
  Solved solved = idr::match(
      state.phase, [](Done &done) { return std::move(done.solved); },
      [](auto &) { return Solved{}; });
  state.phase = Parked{asked.front(), std::move(solved)};
  turn.parked.emplace_back(member, std::move(asked));
  return Outcome::Parks;
}

LogicalResult Scheduler::runMember(FunctionId member, Turn &turn) {
  IDR_ZONE(schedule.symbolOf(member).getValue());
  specialize::Requester &asking = schedule.requesterOf(member);
  while (true) {
    if (failed(round(member)))
      return failure();
    SmallVector<specialize::Node *> asked = asking.take();
    unsigned leaves = schedule.takeLeaves(member);
    if (asked.empty()) {
      if (leaves == 0)
        return success();
      continue;
    }
    FailureOr<Outcome> outcome = parks(member, std::move(asked), turn);
    if (failed(outcome))
      return failure();
    if (*outcome == Outcome::Parks)
      return success();
  }
}

// A function the program held gets its binding times from the bodies of
// the held members taken up with it; a copy inherited its owner's when it
// was built. Each member's are written once, here.
void Scheduler::takeUp(ArrayRef<FunctionId> starters) {
  SmallVector<solver::Member> held;
  for (FunctionId member : starters)
    if (!schedule.members[member.index()].node)
      held.push_back(solver::Member{member, schedule.function(member)});
  std::vector<SmallVector<BindingTime>> solved = bindingTimesOf(schedule.graph, held);
  unsigned next = 0;
  for (FunctionId member : starters) {
    Schedule::Member &state = schedule.members[member.index()];
    SmallVector<BindingTime> times =
        state.node ? std::move(state.inherited) : std::move(solved[next++]);
    state.phase = Done{Solved{std::move(times)}};
  }
}

LogicalResult Scheduler::turn(Turn &work) {
  profile::ThreadTrace trace;
  if (!work.starters.empty())
    takeUp(work.starters);
  for (FunctionId member : work.starters) {
    // A member the debug counter skips is left as it is, done.
    LogicalResult ran = success();
    (void)support::perform<NodeAction>(schedule.function(member),
                                       [&] { ran = runMember(member, work); });
    if (failed(ran))
      return failure();
  }
  for (FunctionId member : work.resumed) {
    Schedule::Member &state = schedule.members[member.index()];
    Solved solved = idr::match(
        state.phase, [](Parked &parked) { return std::move(parked.solved); },
        [](auto &) { return Solved{}; });
    state.phase = Done{std::move(solved)};
    if (failed(runMember(member, work)))
      return failure();
  }
  // Every member done: the component's final bodies state its facts.
  ArrayRef<FunctionId> ids = schedule.byComponent.find(work.component)->second;
  if (!llvm::all_of(ids, [&](FunctionId id) {
        return idr::match(schedule.members[id.index()].phase,
                          [](const Done &) { return true; }, [](const auto &) { return false; });
      }))
    return success();
  work.ends = Turn::Ends::Yes;
  return success();
}

} // namespace idr::optimize
