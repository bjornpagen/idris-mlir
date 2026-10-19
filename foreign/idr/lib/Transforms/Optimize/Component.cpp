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
// A call says what it may do by its own effects, which upstream's
// canonicalize and cse read, and which the component's entry is summed
// from. Each call of a final callee is given the callee's entry when the
// callee becomes final (Waves.cpp); a call made later, of a node final
// before it was asked for again, is given it by its own function's turn,
// before each run of the inner pipeline and before the component's
// summaries are read. A call of a callee not final keeps every effect.
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

#include "idr/Transforms/OptimizeScheduler.h"

#include "idr/Analysis/BindingTimes.h"
#include "idr/Analysis/Constants.h"
#include "idr/Analysis/Identities.h"
#include "idr/Analysis/Inline.h"
#include "idr/IR/Func.h"
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

// Each call in `node`'s body of a callee final now carries the callee's
// entry. The node's turn holds its body.
void writeCallEffects(const ReadySet &set, const Node &node) {
  FuncOp fn = node.fn;
  fn.getBody().walk([&](CallOp call) {
    Callee callee = set.callee(node, call.getCalleeAttr().getAttr());
    if (const auto *known = std::get_if<Final>(&callee))
      call.setEffects(known->summary.effects);
  });
}

} // namespace

Scheduler::Scheduler(Analyses in, RunPipeline run)
    : analyses(in), runPipeline(std::move(run)), inner(FuncOp::getOperationName()) {
  buildInnerPipeline(inner, analyses.inner);
}

LogicalResult Scheduler::runInner(Node *node) {
  writeCallEffects(analyses.set, *node);
  OpPassManager *pm = nullptr;
  {
    std::lock_guard<std::mutex> lock(pipelinesMutex);
    if (idle.empty()) {
      pipelines.push_back(std::make_unique<OpPassManager>(inner));
      idle.push_back(pipelines.back().get());
    }
    pm = idle.pop_back_val();
  }
  LogicalResult result = runPipeline(*pm, node->fn);
  std::lock_guard<std::mutex> lock(pipelinesMutex);
  idle.push_back(pm);
  return result;
}

// The cse counts into statistics of its own, on each copy of the pipeline
// that ran (`inner` never runs); upstream's canonicalize counts nothing.
// MLIR's pass manager reports the statistics of its own pipeline, and a
// pipeline a pass runs through runPipeline is none of it, so the counts are
// read here off the copies, through upstream's own statistics. MLIR names a
// statistic by its pass's argument and its own name, as it prints them, so
// the table below says by those names which of the run's counts each adds
// to. No worker runs once the waves end; the copies are read under their
// lock all the same, as everywhere else.
void Scheduler::addInnerStatistics() {
  const InnerCounts &counts = analyses.inner.counts;
  struct Into {
    StringRef step, statistic;
    Pass::Statistic &total;
  };
  // A copy is matched by the argument MLIR gives its pass, the only name a copy carries.
  const Into into[] = {{"cse", "num-cse'd", counts.cseMerged},
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
  auto callee = [&](StringAttr name) { return set.callee(*node, name); };
  inlining::Step step = inlining::inlineCalls(node->fn, callee);
  turn.inlined += step.inlined;
  turn.capped += step.capped;
  return step.inlined != 0;
}

LogicalResult Scheduler::round(Node *node, Turn &turn) {
  (void)inlineStep(node, turn);
  return runInner(node);
}

// A member that parks moves what its turn solved into its park.
FailureOr<bool> Scheduler::parks(Node *node, SmallVector<specialize::Node *> asked, Turn &turn) {
  if (failed(build(asked, turn)))
    return failure();
  const specialize::Nodes &nodes = analyses.nodes;
  if (llvm::all_of(asked, [&](specialize::Node *made) { return nodes.ready(*made); }))
    return false;
  node->state = Node::Parked{asked.front(), std::move(std::get<Node::Done>(node->state).solved)};
  turn.parked.emplace_back(node, std::move(asked));
  return true;
}

// A member runs done, holding what its turn solved, and stays done unless
// it parks.
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
    if (failed(runInner(node)))
      return failure();
    if (SmallVector<specialize::Node *> asked = nodes.takeRequests(node->fn); !asked.empty()) {
      FailureOr<bool> parked = parks(node, std::move(asked), turn);
      if (failed(parked))
        return failure();
      if (*parked)
        return success();
    }
  }
  return success();
}

// Every callee outside the component is final now, the nodes a member
// asked for among them, so the component's summaries are read off its
// final bodies, its entry from its calls' effects. Nothing outside the
// component reads them before settle makes it final.
Finished Scheduler::finish(const Scc &scc) {
  for (Node *member : scc.members)
    writeCallEffects(analyses.set, *member);
  Finished done{componentEffects(functionsOf(scc.members), analyses.symbols), {}};
  bool shared = scc.members.size() > 1;
  for (Node *member : scc.members)
    done.members.push_back({returnedConstants(member->fn),
                            inlining::factsOf(member->fn, member->calls(),
                                              shared || member->stepOfRecursion())});
  return done;
}

// A function the program held gets its binding times from the bodies of
// the held members taken up with it; a made node inherited its owner's when
// it was built. What each gives back is solved over the members taken up,
// a callee outside them read as its own component's turn or its
// publication left it. Each member's is written once, here, into its
// state: taken up, it is done until it parks.
void Scheduler::takeUp(ArrayRef<Node *> starters) {
  SmallVector<FuncOp> held;
  for (Node *member : starters)
    if (std::holds_alternative<Node::Held>(member->origin))
      held.push_back(member->fn);

  const Node &reader = *starters.front();
  auto outside = [&](StringAttr callee) { return givenBack(analyses.set.callee(reader, callee)); };
  SmallVector<std::optional<unsigned>> given =
      identities::givesBackOf(functionsOf(starters), outside);

  for (auto [member, each] : llvm::zip_equal(starters, given)) {
    Solved solved;
    solved.givesBack = each;
    solved.times = std::visit(
        llvm::makeVisitor([&](Node::Held &) { return bindingTimesOf(member->fn, held); },
                          [](Node::Made &made) { return std::move(made.times); }),
        member->origin);
    member->state = Node::Done{std::move(solved)};
  }
}

LogicalResult Scheduler::turn(Turn &work) {
  profile::ThreadTrace trace;
  // A turn of resumed members alone takes none up.
  if (!work.starters.empty())
    takeUp(work.starters);
  for (Node *member : work.starters) {
    // A member the debug counter skips is left as it is, done.
    LogicalResult ran = success();
    (void)support::perform<NodeAction>(member->fn, [&] { ran = runMember(member, work); });
    if (failed(ran))
      return failure();
  }
  for (Node *member : work.resumed) {
    // Resumed, it runs done again, with what its turn solved.
    member->state = Node::Done{std::move(std::get<Node::Parked>(member->state).solved)};
    if (failed(runMember(member, work)))
      return failure();
  }
  Scc &scc = work.scc;
  if (llvm::all_of(scc.members, [](const Node *member) {
        return std::holds_alternative<Node::Done>(member->state);
      }))
    work.finished = finish(scc);
  return success();
}

} // namespace idr::optimize
