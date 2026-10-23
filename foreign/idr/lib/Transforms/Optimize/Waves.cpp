// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The waves. A wave is every step queued, the turn of every component
// that can go on; its turns run in parallel and touch disjoint components.
// Between two waves no turn runs, and what happens then is Settle.cpp's;
// here the steps that can go on are queued, gathered into one turn per
// component, the members they take up decided (each one's parameters at
// the holds its component passes, its calls of final functions at the
// results their copies will give, its results where its tails or its
// return no longer agree with them), and run, until no step is queued.

#include "idr/Transforms/OptimizeScheduler.h"

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/Remarks.h"
#include "mlir/IR/Threading.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::optimize {

// The queued components that can go on: whose callees are final and that
// are not final themselves; in each, every member not taken up, once none
// of them waits, and each parked member whose waits are met. Leaders in
// order, members in id order: the same at any thread count.
void Scheduler::enable(SmallVectorImpl<Step> &ready) {
  SmallVector<unsigned> leaders;
  for (unsigned queued : check)
    leaders.push_back(schedule.components.findLeader(queued));
  check.clear();
  llvm::sort(leaders);
  leaders.erase(std::unique(leaders.begin(), leaders.end()), leaders.end());
  for (unsigned leader : leaders) {
    ArrayRef<FunctionId> ids = schedule.byComponent[leader];
    if (schedule.unfinished[leader] != 0 ||
        isFinal(schedule.members[ids.front().index()].phase))
      continue;
    bool startable = llvm::none_of(ids, [&](FunctionId id) {
      const Schedule::Member &member = schedule.members[id.index()];
      return !takenUp(member.phase) && member.unmet != 0;
    });
    for (FunctionId id : ids) {
      const Schedule::Member &member = schedule.members[id.index()];
      idr::match(
          member.phase,
          [&](Waiting) {
            if (startable)
              ready.push_back(Start{id});
          },
          [&](const Parked &) {
            if (member.unmet == 0)
              ready.push_back(Resume{id});
          },
          [](const OneOf<Done, Final> auto &) {});
    }
  }
}

// One turn per component, in leader order, its starters and resumed
// members in id order. `enable` queues a component's steps together, the
// leaders in order, so a step of another component than the last begins
// its turn.
SmallVector<Turn, 0> Scheduler::gather(ArrayRef<Step> ready) {
  SmallVector<Turn, 0> wave;
  for (const Step &step : ready) {
    FunctionId id = idr::match(step, [](Start start) { return start.member; },
                               [](const Resume &resume) { return resume.member; });
    unsigned leader = schedule.components.findLeader(id.index());
    if (wave.empty() || wave.back().component != leader)
      wave.emplace_back(leader);
    Turn &turn = wave.back();
    idr::match(
        step, [&](Start start) { turn.starters.push_back(start.member); },
        [&](const Resume &resume) { turn.resumed.push_back(resume.member); });
  }
  return wave;
}

LogicalResult Scheduler::run() {
  MLIRContext *context = schedule.program.getContext();
  for (auto [leader, members] : llvm::enumerate(schedule.byComponent))
    if (!members.empty())
      check.push_back(static_cast<unsigned>(leader));
  SmallVector<Step> ready;
  enable(ready);
  while (!ready.empty()) {
    SmallVector<Turn, 0> wave = gather(ready);
    ready.clear();
    // Each member a turn takes up is decided first, here, where no turn
    // runs: its parameters, its calls and its results, each member of its
    // component a decision reaches decided again in turn. The decisions
    // rewrite its callers, each of which waits on it, not taken up, or is
    // of its component, and restate a copy's signature on its node, which
    // the turns then read.
    for (const Turn &work : wave)
      specialize::openResults(schedule, nodes, work.starters);
    // The turns are disjoint, so the output is theirs in any order; the
    // context runs them one after another when its threading is off, as it
    // is while an action handler counts.
    if (failed(failableParallelForEach(context, wave, [&](Turn &work) { return turn(work); })))
      return failure();
    if (failed(settle(wave)))
      return failure();
    if (remark::detail::InFlightRemark progress = remark::analysis(
            schedule.program.getLoc(), remark::RemarkOpts::name("progress").category("idr-optimize")))
      progress << remark::metric("functions", schedule.members.size())
               << remark::metric("made", numMade);
    enable(ready);
  }
  // A gap in the ids holds no function, and nothing schedules it. A member
  // is read through a const reference and its function is reported on: its
  // handle is copied out, as an op is passed.
  for (const Schedule::Member &member : schedule.members) {
    FuncOp fn = member.fn;
    if (fn && !isFinal(member.phase))
      return fn.emitError() << "internal error: idr-optimize: the schedule stopped with @"
                            << fn.getSymName() << " not final";
  }
  return success();
}

} // namespace idr::optimize
