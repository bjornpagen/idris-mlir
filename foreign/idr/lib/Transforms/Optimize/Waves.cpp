// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The waves, and what happens between them on the pass thread.
//
// A wave is the turn of every component that can go on, read off what is
// final; its turns run in parallel and touch disjoint components. Between
// two waves no turn runs, so this is where the module, its symbol table,
// the ready set's maps and the analysis manager's children change: the
// pass's pipeline on a function nests an analysis manager for it, and
// nesting a new function inserts into a map that pipelines on other
// functions read. So the nodes the turns built go into the module here,
// after their owners and by name, the components that finished become
// final, and the requests the turns could not follow are recorded as waits
// on the nodes they name.
//
// A request may close a cycle: a node asks for one that is parked, through
// requests, on the asker's own component. Every component on the cycle
// then becomes one, whose members finish together and never inline one
// another. Each wave's waits are recorded in a fixed order, built nodes by
// name after the turns in wave order, and the cycles they close do not
// depend on that order, so neither do the components.

#include "idr/Transforms/Optimize.h"

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/Remarks.h"
#include "mlir/IR/Threading.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallPtrSet.h"

using namespace mlir;

namespace idr::optimize {

// The components that can go on, in the ready set's order: those whose
// callees are final, each with the members it takes up (all of those not
// taken up yet, once every one of them is in the module and parked on
// nothing) and the parked members whose waits are all met.
SmallVector<Turn> Scheduler::nextWave() {
  SmallVector<Turn> wave;
  for (const std::unique_ptr<Scc> &owned : analyses.set.sccs) {
    Scc &scc = *owned;
    if (scc.mergedInto || scc.unfinishedCallees != 0 || scc.members.empty() ||
        scc.members.front()->isFinal())
      continue;
    Turn turn;
    turn.scc = &scc;
    bool startable = true;
    SmallVector<Node *> unstarted;
    for (Node *member : scc.members) {
      switch (member->state) {
      case Node::State::Unbuilt:
        startable = false;
        break;
      case Node::State::Waiting:
        startable = startable && member->inModule && member->waitsOn.empty();
        unstarted.push_back(member);
        break;
      case Node::State::Parked:
        if (member->waitsOn.empty())
          turn.resumed.push_back(member);
        break;
      case Node::State::Done:
        break;
      }
    }
    if (startable)
      turn.starters = std::move(unstarted);
    if (!turn.starters.empty() || !turn.resumed.empty())
      wave.push_back(std::move(turn));
  }
  return wave;
}

// The ready-set node of a node of the table, made the first time it is
// asked for, with a component of its own whose callees, its owner's, are
// all final.
Node *Scheduler::nodeOfMade(specialize::Node *made) {
  ReadySet &set = analyses.set;
  if (Node *found = set.byMade.lookup(made))
    return found;
  auto node = std::make_unique<Node>();
  node->made = made;
  node->facts.calls = 1;
  node->state = Node::State::Unbuilt;
  node->inModule = false;
  auto scc = std::make_unique<Scc>();
  scc->members.push_back(node.get());
  node->scc = scc.get();
  Node *out = node.get();
  set.byMade.try_emplace(made, out);
  set.all.push_back(std::move(node));
  set.sccs.push_back(std::move(scc));
  return out;
}

// Whether a member of `from` is parked, through requests, on a member of
// `to`.
bool Scheduler::reaches(Scc &from, Scc &to) {
  llvm::SmallPtrSet<Scc *, 8> seen{&from};
  SmallVector<Scc *> work{&from};
  while (!work.empty()) {
    Scc *at = work.pop_back_val();
    for (Node *member : at->members) {
      for (Node *target : member->waitsOn) {
        Scc *next = &target->scc->leader();
        if (next == &to)
          return true;
        if (seen.insert(next).second)
          work.push_back(next);
      }
    }
  }
  return false;
}

// Every component on a path of waits from `from` to `into` joins `into`,
// and the waits between its members go. Only made nodes are waited on, so
// every component a merge takes in is a made node's.
LogicalResult Scheduler::merge(Scc &into, Scc &from) {
  SmallVector<Scc *> forward{&from};
  llvm::SmallPtrSet<Scc *, 8> seen{&from};
  for (size_t at = 0; at < forward.size(); ++at)
    for (Node *member : forward[at]->members)
      for (Node *target : member->waitsOn)
        if (Scc *next = &target->scc->leader(); next != &into && seen.insert(next).second)
          forward.push_back(next);
  for (Scc *scc : forward) {
    if (scc != &from && !reaches(*scc, into))
      continue;
    if (!scc->callers.empty() || scc->unfinishedCallees != 0)
      return analyses.module.emitError("internal error: idr-optimize: a cycle of requests "
                                       "reaches a function the module held");
    for (Node *member : scc->members) {
      member->scc = &into;
      into.members.push_back(member);
    }
    scc->members.clear();
    scc->mergedInto = &into;
  }
  for (Node *member : into.members) {
    llvm::erase_if(member->waitsOn, [&](Node *target) {
      if (&target->scc->leader() != &into)
        return false;
      llvm::erase(target->waiters, member);
      return true;
    });
  }
  return success();
}

// `requester` asked for `node`: nothing to wait on when the node is final
// or in its own component; a wait otherwise, or a merge when the wait
// would close a cycle.
LogicalResult Scheduler::want(Node *requester, Node *node) {
  if (node->isFinal())
    return success();
  Scc &mine = requester->scc->leader();
  Scc &theirs = node->scc->leader();
  if (&mine == &theirs)
    return success();
  if (reaches(theirs, mine))
    return merge(mine, theirs);
  if (!llvm::is_contained(requester->waitsOn, node)) {
    requester->waitsOn.push_back(node);
    node->waiters.push_back(requester);
  }
  return success();
}

// A built node goes into the module: after its owner and the owner's nodes
// whose names sort before its own (the table places it), into the symbol
// table and the ready set's map, and into the analysis manager.
LogicalResult Scheduler::insert(Node *node) {
  StringAttr name = node->fn.getSymNameAttr();
  // A name is its key's, so a function already holding it is a collision
  // of the hash, never a reason to rename.
  if (analyses.symbols.lookup(name))
    return node->fn.emitError() << "internal error: idr-optimize: the specialization @"
                                << name.getValue() << " meets a function of the module";
  analyses.nodes.insert(*node->made, analyses.module);
  analyses.symbols.insert(node->fn);
  analyses.set.byName.try_emplace(name, node);
  (void)analyses.am.nest(node->fn);
  node->inModule = true;
  ++numMade;
  return success();
}

void Scheduler::finalize(Scc &scc) {
  for (Node *member : scc.members) {
    member->final = true;
    ++numFinal;
  }
  for (Scc *caller : scc.callers)
    --caller->leader().unfinishedCallees;
  for (Node *member : scc.members) {
    for (Node *waiter : member->waiters)
      llvm::erase(waiter->waitsOn, member);
    member->waiters.clear();
  }
}

LogicalResult Scheduler::settle(MutableArrayRef<Turn> wave) {
  SmallVector<std::pair<specialize::Node *, SmallVector<specialize::Node *>>> built;
  SmallVector<Node *> requesters;
  for (Turn &turn : wave) {
    numInlined += turn.inlined;
    numCapped += turn.capped;
    llvm::append_range(built, turn.built);
    for (Node *member : llvm::concat<Node *>(turn.starters, turn.resumed))
      if (member->state == Node::State::Parked)
        requesters.push_back(member);
  }
  // Which turn built a node changes nothing; the name fixes the order.
  llvm::sort(built, [](const auto &lhs, const auto &rhs) {
    return lhs.first->name.getValue() < rhs.first->name.getValue();
  });
  for (auto &[made, requests] : built) {
    Node *node = nodeOfMade(made);
    node->fn = made->fn;
    node->state = Node::State::Waiting;
    if (failed(insert(node)))
      return failure();
  }
  for (Turn &turn : wave)
    if (turn.finished)
      finalize(*turn.scc);
  for (Node *requester : requesters) {
    for (specialize::Node *made : requester->asked)
      if (failed(want(requester, nodeOfMade(made))))
        return failure();
    requester->asked.clear();
  }
  for (auto &[made, requests] : built)
    for (specialize::Node *request : requests)
      if (failed(want(analyses.set.byMade.lookup(made), nodeOfMade(request))))
        return failure();
  return success();
}

LogicalResult Scheduler::run() {
  MLIRContext *context = analyses.module.getContext();
  while (true) {
    SmallVector<Turn> wave = nextWave();
    if (wave.empty())
      break;
    if (failed(failableParallelForEach(context, wave, [&](Turn &work) { return turn(work); })))
      return failure();
    if (failed(settle(wave)))
      return failure();
    // From the pass thread, where no turn runs: how far the run is.
    if (remark::detail::InFlightRemark progress = remark::analysis(
            analyses.module.getLoc(), remark::RemarkOpts::name("progress").category("idr-optimize")))
      progress << remark::metric("final", numFinal) << remark::metric("nodes", analyses.set.all.size())
               << remark::metric("made", numMade);
  }
  for (const std::unique_ptr<Node> &node : analyses.set.all) {
    if (node->isFinal())
      continue;
    if (node->fn)
      return node->fn.emitError() << "internal error: idr-optimize: the ready set stopped with @"
                                  << node->fn.getSymName() << " not final";
    return analyses.module.emitError() << "internal error: idr-optimize: the ready set stopped "
                                          "with @"
                                       << node->made->name.getValue() << " never built";
  }
  return success();
}

} // namespace idr::optimize
