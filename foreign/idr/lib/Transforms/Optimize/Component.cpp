// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// One component's turn in a wave, on a worker. A turn reads its own
// members, the functions final before the wave and nothing else, and
// writes its own members alone: every component of a wave is another, so
// the turns run in parallel and each is a function of what it reads.
//
// A member taken up first gets its calls' effects and its component's
// binding times and identities; then each member runs its loop: inline its
// calls into final callees, run the inner pipeline, and follow what the
// pipeline's redirect step requested. A request of a node final before the
// wave is followed at once; any other parks the member until the wave
// ends, since only then is the node in the module and taken up. A member
// resumed runs the pipeline once more, so a call of a node now final takes
// the node's effects. The loop ends when an iteration after the first
// inlines nothing and follows no request: every inline takes a call into a
// final callee, the final callees below a function are a finite DAG whose
// cycles are never inlined, and the keys a function can request are finite
// and requested once.

#include "idr/Transforms/Optimize.h"

#include "idr/Analysis/Constants.h"
#include "idr/Analysis/Effects.h"
#include "idr/Analysis/Identities.h"
#include "idr/Analysis/Inline.h"
#include "idr/Analysis/Specialize.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Profile.h"
#include "idr/Transforms/Inline.h"

#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::optimize {

namespace {

SmallVector<FuncOp> functionsOf(ArrayRef<Node *> members) {
  SmallVector<FuncOp> fns;
  for (Node *member : members)
    fns.push_back(member->fn);
  return fns;
}

// What the rule reads of a final body besides its size: whether it calls
// anything, and whether it calls itself.
void readCalls(FuncOp fn, bool &leaf, bool &self) {
  leaf = true;
  self = false;
  StringAttr name = fn.getSymNameAttr();
  fn.getBody().walk([&](CallOp call) {
    leaf = false;
    self = self || call.getCalleeAttr().getAttr() == name;
  });
}

} // namespace

Scheduler::Scheduler(Analyses in, RunPipeline run)
    : analyses(in), runPipeline(std::move(run)), inner(FuncOp::getOperationName()) {
  buildInnerPipeline(inner);
}

LogicalResult Scheduler::runInner(FuncOp fn) {
  OpPassManager *pm = nullptr;
  {
    std::lock_guard<std::mutex> lock(pipelinesMutex);
    if (idle.empty()) {
      pipelines.push_back(std::make_unique<OpPassManager>(inner));
      idle.push_back(pipelines.back().get());
    }
    pm = idle.pop_back_val();
  }
  LogicalResult result = runPipeline(*pm, fn);
  std::lock_guard<std::mutex> lock(pipelinesMutex);
  idle.push_back(pm);
  return result;
}

// The table gives each node to one claimant, which builds it detached: the
// build reads only its owner, which is final. Which turn of a wave builds
// a node changes nothing, since its body is a function of its key and its
// owner.
LogicalResult Scheduler::build(ArrayRef<specialize::Node *> requests, Turn &turn) {
  const specialize::Nodes &nodes = analyses.nodes;
  for (specialize::Node *made : requests) {
    if (!nodes.claim(*made))
      continue;
    if (failed(nodes.build(*made)))
      return failure();
    SmallVector<specialize::Node *> more = nodes.takeRequests(made->fn);
    turn.built.push_back({made, more});
    if (failed(build(more, turn)))
      return failure();
  }
  return success();
}

FailureOr<bool> Scheduler::runMember(Node *node, bool resumed, Turn &turn) {
  IDR_ZONE(node->fn.getSymName());
  const ReadySet &set = analyses.set;
  auto nodeOf = [&](StringAttr name) -> const Node * { return set.nodeOf(name); };
  bool first = !resumed;
  bool asked = resumed;
  while (true) {
    inlining::Step step = inlining::inlineCalls(node->fn, nodeOf);
    turn.inlined += step.inlined;
    turn.capped += step.capped;
    if (!first && step.inlined == 0 && !asked)
      return false;
    if (failed(runInner(node->fn)))
      return failure();
    first = false;
    SmallVector<specialize::Node *> requests = analyses.nodes.takeRequests(node->fn);
    asked = !requests.empty();
    if (failed(build(requests, turn)))
      return failure();
    bool waits = llvm::any_of(requests, [&](specialize::Node *made) {
      Node *target = set.byMade.lookup(made);
      return !target || !target->isFinal();
    });
    if (waits) {
      node->asked = std::move(requests);
      return true;
    }
  }
}

void Scheduler::finish(Scc &scc) {
  SmallVector<FuncOp> fns = functionsOf(scc.members);
  // Every callee outside the component is final now, the nodes a member
  // asked for among them: a call redirected to one before it was final
  // takes its entry here, then the entries and the calls inside follow.
  writeCallEffectsOnReady(fns, analyses.symbols);
  writeEntriesOnFinal(fns, analyses.holds, analyses.symbols);
  analyses.summaries.publish(fns);
  for (Node *member : scc.members) {
    bool self = false;
    member->facts.size = inlineSize(member->fn);
    readCalls(member->fn, member->facts.leaf, self);
    member->facts.onCycle = scc.members.size() > 1 || self;
  }
}

LogicalResult Scheduler::turn(Turn &work) {
  profile::ThreadTrace trace;
  if (!work.starters.empty()) {
    SmallVector<FuncOp> fns = functionsOf(work.starters);
    // First: identities rely on a callee returning by the effects its
    // calls carry.
    writeCallEffectsOnReady(fns, analyses.symbols);
    analyses.times.solve(fns);
    analyses.identities.solve(fns);
  }
  for (Node *member : work.starters) {
    FailureOr<bool> parked = false;
    // A member the debug counter skips is left as it is, done.
    (void)support::perform<NodeAction>(member->fn,
                                       [&] { parked = runMember(member, false, work); });
    if (failed(parked))
      return failure();
    member->state = *parked ? Node::State::Parked : Node::State::Done;
  }
  for (Node *member : work.resumed) {
    FailureOr<bool> parked = runMember(member, true, work);
    if (failed(parked))
      return failure();
    member->state = *parked ? Node::State::Parked : Node::State::Done;
  }
  Scc &scc = *work.scc;
  work.finished = llvm::all_of(scc.members, [](Node *member) {
    return member->state == Node::State::Done;
  });
  if (work.finished)
    finish(scc);
  return success();
}

} // namespace idr::optimize
