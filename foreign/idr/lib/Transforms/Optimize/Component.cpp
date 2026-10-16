// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// One component's turn in a wave, on a worker. A turn reads its own
// members, the functions final before the wave and nothing else, and
// writes its own members alone: every component of a wave is another, so
// the turns run in parallel and each is a function of what it reads.
//
// The members a turn takes up get their binding times and what they give
// back, solved over them; then each member runs its loop: a round (inline
// its calls into final callees, then run the inner pipeline), and another
// round for each batch of nodes the pipeline's redirect step was given,
// once every node of the batch is final. A batch with a node not final
// before the wave parks the member until the wave ends, since only then is
// the node in the program and taken up; resumed, the member runs a round,
// so a call of a node now final is read with the node's summary.
//
// The loop ends because a member is given finitely many nodes: the table
// judges every request of a function, its own and those of the code
// inlined into it alike, against the keys it was given before, which
// bounds them. Each batch takes nodes the member was never given before,
// so the batches are finitely many, and so are the parks. A redirect to a node given before
// names no new node, so after the batches one fixed step takes such a call
// in: one more inline step, then, when it inlined anything, the pipeline
// once more and the batch it asks for, built and followed no further than
// a park. A call that step leaves is a call: a spent step only leaves the
// program less optimized. When every member is done the component's
// summaries are read off its final bodies; they are published between
// waves.

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

// What the inline rule reads of a final body: its size, whether it calls
// anything, and whether it is on a cycle: a member of a component of two
// or more, or a body that calls itself.
inlining::Facts factsOf(FuncOp fn, unsigned calls, bool shared) {
  inlining::Facts facts;
  facts.size = inlineSize(fn);
  facts.calls = calls;
  facts.leaf = true;
  facts.onCycle = shared;
  StringAttr name = fn.getSymNameAttr();
  fn.getBody().walk([&](CallOp call) {
    facts.leaf = false;
    facts.onCycle = facts.onCycle || call.getCalleeAttr().getAttr() == name;
  });
  return facts;
}

} // namespace

Scheduler::Scheduler(Analyses in, RunPipeline run)
    : analyses(in), runPipeline(std::move(run)), inner(FuncOp::getOperationName()) {
  buildInnerPipeline(inner, analyses.inner);
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

// The canonicalizer and cse count into statistics of their own, on each
// copy of the pipeline that ran (`inner` never runs). MLIR's pass manager
// reports the statistics of its own pipeline, and a pipeline a pass runs
// through runPipeline is none of it, so the counts are read here off the
// copies, through upstream's own statistics. MLIR names a statistic by its
// pass's argument and its own name, as it prints them, so the table below
// says by those names which of the run's counts each adds to. No worker
// runs once the waves end; the copies are read under their lock all the
// same, as everywhere else.
void Scheduler::addInnerStatistics() {
  const InnerCounts &counts = analyses.inner.counts;
  struct Into {
    StringRef step, statistic;
    Pass::Statistic &total;
  };
  // A copy is matched by the argument MLIR gives its pass, the only name a copy carries.
  const Into into[] = {{"idr-canonicalize", "not-converged", counts.notConverged},
                       {"cse", "num-cse'd", counts.cseMerged},
                       {"cse", "num-dce'd", counts.cseErased}};
  std::lock_guard<std::mutex> lock(pipelinesMutex);
  for (const std::unique_ptr<OpPassManager> &pm : pipelines)
    for (Pass &pass : pm->getPasses())
      for (Pass::Statistic *statistic : pass.getStatistics())
        for (const Into &each : into)
          if (pass.getArgument() == each.step && StringRef(statistic->getName()) == each.statistic)
            each.total += statistic->getValue();
}

// The table gives each node to one claimant, which builds it detached: the
// build reads only its owner, which is final, and requests nothing, the
// node's calls being its own turns' to redirect. Which turn of a wave
// builds a node changes nothing, since its body is a function of its key
// and its owner.
LogicalResult Scheduler::build(ArrayRef<specialize::Node *> requests, Turn &turn) {
  const specialize::Nodes &nodes = analyses.nodes;
  for (specialize::Node *made : requests) {
    if (!nodes.claim(*made))
      continue;
    if (failed(nodes.build(*made)))
      return failure();
    turn.built.push_back(made);
  }
  return success();
}

bool Scheduler::inlineStep(Node *node, Turn &turn) {
  const ReadySet &set = analyses.set;
  auto nodeOf = [&](StringAttr name) -> const Node * { return set.nodeOf(name); };
  inlining::Step step = inlining::inlineCalls(node->fn, nodeOf);
  turn.inlined += step.inlined;
  turn.capped += step.capped;
  return step.inlined != 0;
}

LogicalResult Scheduler::round(Node *node, Turn &turn) {
  (void)inlineStep(node, turn);
  return runInner(node->fn);
}

FailureOr<bool> Scheduler::parks(Node *node, SmallVector<specialize::Node *> asked, Turn &turn) {
  if (failed(build(asked, turn)))
    return failure();
  const ReadySet &set = analyses.set;
  bool waits = llvm::any_of(asked, [&](specialize::Node *made) {
    Node *target = set.byMade.lookup(made);
    return !target || !target->isFinal();
  });
  if (!waits)
    return false;
  node->state = Node::Parked{asked.front()};
  turn.parked.emplace_back(node, std::move(asked));
  return true;
}

LogicalResult Scheduler::runMember(Node *node, Turn &turn) {
  IDR_ZONE(node->fn.getSymName());
  const specialize::Nodes &nodes = analyses.nodes;
  if (failed(round(node, turn)))
    return failure();
  for (SmallVector<specialize::Node *> asked = nodes.takeRequests(node->fn); !asked.empty();
       asked = nodes.takeRequests(node->fn)) {
    FailureOr<bool> parked = parks(node, std::move(asked), turn);
    if (failed(parked))
      return failure();
    if (*parked)
      return success();
    if (failed(round(node, turn)))
      return failure();
  }
  // The fixed last step: a call the last pipeline redirected to a node the
  // member was given before is inlined here, and the pipeline cleans what
  // that brought, its batch built and followed no further than a park.
  if (inlineStep(node, turn)) {
    if (failed(runInner(node->fn)))
      return failure();
    if (SmallVector<specialize::Node *> asked = nodes.takeRequests(node->fn); !asked.empty()) {
      FailureOr<bool> parked = parks(node, std::move(asked), turn);
      if (failed(parked))
        return failure();
      if (*parked)
        return success();
    }
  }
  node->state = Node::Done{};
  return success();
}

// Every callee outside the component is final now, the nodes a member
// asked for among them, so the component's summaries are read off its
// final bodies. Nothing outside the component reads them before settle
// makes it final.
Finished Scheduler::finish(const Scc &scc) {
  Finished done{componentEffects(functionsOf(scc.members), analyses.symbols), {}};
  bool shared = scc.members.size() > 1;
  for (Node *member : scc.members)
    done.members.push_back(
        {returnedConstants(member->fn), factsOf(member->fn, member->calls(), shared)});
  return done;
}

// A function the program held gets its binding times from the bodies of
// the members taken up with it; a made node inherited its owner's when it
// was built. What each gives back is solved over the members taken up, a
// callee outside them read as its own component's turn or its publication
// left it. Each member's is written once, here.
void Scheduler::takeUp(ArrayRef<Node *> starters) {
  SmallVector<Node *> held;
  for (Node *member : starters)
    if (std::holds_alternative<Node::Held>(member->origin))
      held.push_back(member);
  SmallVector<SmallVector<BindingTime>> times = bindingTimesOf(functionsOf(held));

  const Node &reader = *starters.front();
  auto outside = [&](StringAttr callee) -> identities::Callee {
    FuncOp fn = analyses.set.lookup(callee);
    return {analyses.set.givesBack(reader, callee),
            fn && !bitEnumContainsAny(fn.getEffects(), Effect::diverge)};
  };
  SmallVector<std::optional<unsigned>> given =
      identities::givesBackOf(functionsOf(starters), outside, analyses.inner.effects);

  auto heldTimes = times.begin();
  for (auto [member, each] : llvm::zip_equal(starters, given)) {
    Solved solved;
    solved.givesBack = each;
    solved.times = std::visit(
        llvm::makeVisitor([&](Node::Held &) { return std::move(*heldTimes++); },
                          [](Node::Made &made) { return std::move(made.times); }),
        member->origin);
    member->solved = std::move(solved);
  }
}

LogicalResult Scheduler::turn(Turn &work) {
  profile::ThreadTrace trace;
  if (!work.starters.empty())
    takeUp(work.starters);
  for (Node *member : work.starters) {
    // A member the debug counter skips is left as it is, done.
    member->state = Node::Done{};
    LogicalResult ran = success();
    (void)support::perform<NodeAction>(member->fn, [&] { ran = runMember(member, work); });
    if (failed(ran))
      return failure();
  }
  for (Node *member : work.resumed)
    if (failed(runMember(member, work)))
      return failure();
  Scc &scc = work.scc;
  if (llvm::all_of(scc.members, [](const Node *member) {
        return std::holds_alternative<Node::Done>(member->state);
      }))
    work.finished = finish(scc);
  return success();
}

} // namespace idr::optimize
