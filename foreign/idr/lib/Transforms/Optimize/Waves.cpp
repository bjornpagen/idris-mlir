// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The waves, and what happens between them on the pass thread.
//
// A wave is every step queued, the turn of every component that can go on;
// its turns run in parallel and touch disjoint components. Each step enters
// the worklist of steps once, so the waves end. Between two waves no turn
// runs, so this is where the program, its symbol table,
// the ready set's maps, the summaries' publication and the analysis
// manager's children change: the pass's pipeline on a function nests an
// analysis manager for it, and nesting a new function inserts into a map
// that pipelines on other functions read. So the nodes the turns built go
// into the program here, after their owners and by name, the components
// that finished become final and publish their summaries, and the requests
// the turns could not follow are recorded as waits on the nodes they name.
// A wait is a fact that stays: it is met once its target is final or one
// component with its waiter, which is read where it is asked.
//
// A made node waits, as every function does, on what it calls: a raise
// node's body takes in its requester's dispatch, which may call the
// requester's own component, not final yet. So each built node waits on
// every function it calls that is not final.
//
// A wait may close a cycle: a node waits on one that waits, through
// requests and calls, on the node's own component. Every component on the
// cycle then becomes one, whose members finish together and never inline
// one another. Each wave's waits are recorded in a fixed order, built nodes
// by name after the turns in wave order, and the cycles they close do not
// depend on that order, so neither do the components.

#include "idr/Transforms/Optimize.h"

#include "idr/Analysis/Effects.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/Remarks.h"
#include "mlir/IR/Threading.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallPtrSet.h"
#include "llvm/ADT/SmallVector.h"

#include <cassert>

using namespace mlir;

namespace idr::optimize {

// Queues the step of every member that can go on: in each component whose
// callees are final and that is not final itself, every member not taken
// up, once none of them waits, and each parked member that no longer
// waits. No step queued here entered before: a member taken up is never
// waiting again, and a resumed one is done or parked on another batch.
void Scheduler::enable(OnceWorklist<Step> &ready) {
  auto queue = [&](const Step &step) {
    [[maybe_unused]] bool fresh = ready.push(step);
    assert(fresh && "a step is queued once");
  };
  for (const std::unique_ptr<Scc> &owned : analyses.set.sccs) {
    Scc &scc = *owned;
    if (scc.members.empty() || scc.unfinishedCallees != 0 || scc.members.front()->isFinal())
      continue;
    bool startable = llvm::none_of(scc.members, [](const Node *member) {
      return std::holds_alternative<Node::Waiting>(member->state) && member->waiting();
    });
    for (Node *member : scc.members)
      std::visit(llvm::makeVisitor(
                     [&](const Node::Waiting &) {
                       if (startable)
                         queue(Start{member});
                     },
                     [&](const Node::Parked &parked) {
                       if (!member->waiting())
                         queue(Resume{member, parked.on});
                     },
                     [](const Node::Done &) {}),
                 member->state);
  }
}

// The wave of `first` and of every other step queued: one turn per
// component, in the ready set's order, its starters and resumed members in
// the component's order, whatever order the steps were queued in.
SmallVector<Turn, 0> Scheduler::gather(const Step &first, OnceWorklist<Step> &ready) {
  llvm::SmallPtrSet<Node *, 16> stepped;
  llvm::SmallPtrSet<Scc *, 8> seen;
  SmallVector<Scc *> sccs;
  auto take = [&](const Step &step) {
    Node *node = std::visit(llvm::makeVisitor([](Start start) { return start; },
                                              [](const Resume &resume) { return resume.first; }),
                            step);
    stepped.insert(node);
    if (seen.insert(node->scc).second)
      sccs.push_back(node->scc);
  };
  take(first);
  while (std::optional<Step> step = ready.pop())
    take(*step);
  llvm::sort(sccs, [](const Scc *lhs, const Scc *rhs) { return lhs->order < rhs->order; });
  SmallVector<Turn, 0> wave;
  for (Scc *scc : sccs) {
    Turn &turn = wave.emplace_back(*scc);
    for (Node *member : scc->members)
      if (stepped.contains(member))
        (std::holds_alternative<Node::Waiting>(member->state) ? turn.starters : turn.resumed)
            .push_back(member);
  }
  return wave;
}

// Whether a member of `from` waits, through requests and calls, on a member
// of `to`. Each component is read once.
bool Scheduler::reaches(Scc &from, Scc &to) {
  OnceWorklist<Scc *> work;
  work.push(&from);
  while (std::optional<Scc *> at = work.pop())
    for (Node *member : (*at)->members)
      for (Node *target : member->waitsOn) {
        if (target->isFinal())
          continue;
        if (target->scc == &to)
          return true;
        work.push(target->scc);
      }
  return false;
}

// Every component on a path of waits from `from` to `into` joins `into`,
// and the waits between its members are met, as waits within one
// component are. A component on such a path has a member waiting, so it
// was taken up, or it is a made node's own: either way its callees are all
// final, and only its callers carry over. A caller keeps one count per
// component it called, so its entries stay one per component that was
// merged.
void Scheduler::merge(Scc &into, Scc &from) {
  // What `from` waits on, each component once, in the order met.
  OnceWorklist<Scc *> work;
  work.push(&from);
  SmallVector<Scc *> forward;
  while (std::optional<Scc *> at = work.pop()) {
    forward.push_back(*at);
    for (Node *member : (*at)->members)
      for (Node *target : member->waitsOn)
        if (!target->isFinal() && target->scc != &into)
          work.push(target->scc);
  }
  for (Scc *scc : forward) {
    if (scc != &from && !reaches(*scc, into))
      continue;
    assert(scc->unfinishedCallees == 0 && "a component on a path of waits has its callees final");
    for (Node *member : scc->members) {
      member->scc = &into;
      into.members.push_back(member);
    }
    llvm::append_range(into.callers, scc->callers);
    scc->members.clear();
    scc->callers.clear();
  }
}

// `requester` waits on `node`, which it asked for or calls: nothing to wait
// on when the node is final or in its own component; a wait otherwise, or
// a merge when the wait would close a cycle.
void Scheduler::want(Node *requester, Node *node) {
  if (node->isFinal())
    return;
  Scc &mine = *requester->scc;
  Scc &theirs = *node->scc;
  if (&mine == &theirs)
    return;
  if (reaches(theirs, mine))
    return merge(mine, theirs);
  if (!llvm::is_contained(requester->waitsOn, node))
    requester->waitsOn.push_back(node);
}

// A built node waits on each function its body calls that is not final.
// Its body is its owner's, with a requester's dispatch for a raise, and its
// build redirected nothing, so every callee is a function of the program.
void Scheduler::waitOnCalls(Node *node) {
  SmallVector<Node *> callees;
  node->fn.getBody().walk(
      [&](CallOp call) { callees.push_back(analyses.set.nodeOf(call.getCalleeAttr().getAttr())); });
  for (Node *callee : callees) {
    assert(callee && "a built node calls functions of the program");
    want(node, callee);
  }
}

// A built node goes into the program: after its owner and the owner's nodes
// whose names sort before its own (the table places it), into the symbol
// table, the analysis manager and the ready set, as a node of a component
// of its own. Its name is its key's, which the table checked against every
// function of the program when the key was first asked for.
void Scheduler::insert(specialize::Node *made) {
  ReadySet &set = analyses.set;
  auto scc = std::make_unique<Scc>();
  scc->order = static_cast<unsigned>(set.sccs.size());
  auto node = std::make_unique<Node>(made->fn, Node::Made{std::move(made->times)}, *scc);
  scc->members.push_back(node.get());
  analyses.nodes.insert(*made, analyses.program);
  analyses.symbols.insert(node->fn);
  (void)analyses.am.nest(node->fn);
  set.byName.try_emplace(node->fn.getSymNameAttr(), node.get());
  set.byMade.try_emplace(made, node.get());
  set.all.push_back(std::move(node));
  set.sccs.push_back(std::move(scc));
  ++numMade;
}

// The component's summaries are written, each whole from what its turn
// solved and what its final body says, and become readable by every other
// component; its entry becomes its members' `effects`, which the passes of
// every later wave read.
void Scheduler::finalize(Scc &scc, Finished done) {
  for (auto [member, body] : llvm::zip_equal(scc.members, done.members)) {
    setEntry(member->fn, done.effects);
    Solved &solved = *member->solved;
    member->published.emplace(Summary{done.effects, solved.givesBack, std::move(solved.times),
                                      std::move(body.constants), body.facts});
    member->solved.reset();
    ++numFinal;
  }
  for (Node *caller : scc.callers)
    --caller->scc->unfinishedCallees;
}

void Scheduler::settle(MutableArrayRef<Turn> wave) {
  SmallVector<specialize::Node *> built;
  for (Turn &turn : wave) {
    numInlined += turn.inlined;
    numCapped += turn.capped;
    llvm::append_range(built, turn.built);
  }
  // Which turn built a node changes nothing; the name fixes the order.
  llvm::sort(built, [](specialize::Node *lhs, specialize::Node *rhs) {
    return lhs->name.getValue() < rhs->name.getValue();
  });
  for (specialize::Node *made : built)
    insert(made);
  for (Turn &turn : wave)
    if (turn.finished)
      finalize(turn.scc, std::move(*turn.finished));
  // A node asked for was claimed and built by a turn of the wave that asked
  // for it, so it is in the ready set now.
  for (Turn &turn : wave)
    for (auto &[requester, asked] : turn.parked)
      for (specialize::Node *made : asked)
        want(requester, analyses.set.byMade.find(made)->second);
  for (specialize::Node *made : built)
    waitOnCalls(analyses.set.byMade.find(made)->second);
}

LogicalResult Scheduler::run() {
  MLIRContext *context = analyses.program.getContext();
  OnceWorklist<Step> ready;
  enable(ready);
  while (std::optional<Step> first = ready.pop()) {
    SmallVector<Turn, 0> wave = gather(*first, ready);
    // An action handler (a debug counter, an action log) counts and writes
    // from one thread: while the context has one, the wave's turns run one
    // after another, in wave order. The turns are disjoint, so the output
    // is the same either way.
    LogicalResult ran = success();
    if (context->hasActionHandler())
      ran = success(llvm::all_of(wave, [&](Turn &work) { return succeeded(turn(work)); }));
    else
      ran = failableParallelForEach(context, wave, [&](Turn &work) { return turn(work); });
    if (failed(ran))
      return failure();
    settle(wave);
    // From the pass thread, where no turn runs: how far the run is.
    if (remark::detail::InFlightRemark progress = remark::analysis(
            analyses.program.getLoc(), remark::RemarkOpts::name("progress").category("idr-optimize")))
      progress << remark::metric("final", numFinal) << remark::metric("nodes", analyses.set.all.size())
               << remark::metric("made", numMade);
    enable(ready);
  }
  for (const std::unique_ptr<Node> &node : analyses.set.all)
    if (!node->isFinal())
      return node->fn.emitError() << "internal error: idr-optimize: the ready set stopped with @"
                                  << node->fn.getSymName() << " not final";
  return success();
}

} // namespace idr::optimize
