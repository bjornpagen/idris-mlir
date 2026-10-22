// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The waves, and what happens between them on the pass thread.
//
// A wave is every step queued, the turn of every component that can go on;
// its turns run in parallel and touch disjoint components. Between two
// waves no turn runs, so this is where the program, the graph's editor, the
// schedule's tables and the analysis manager's children change: a pipeline
// on a function nests an analysis manager for it, and nesting a new
// function inserts into a map that pipelines on other functions read. So
// the copies the turns built go into the program here, by name, the
// components that finished become final, and the waits the turns recorded
// are counted.
//
// A copy waits, as every function does, on what it calls: a raise copy
// takes in its requester's dispatch, which may call the requester's own
// component, not final yet. A wait may close a cycle: a function waits on
// one that waits, through requests and calls, on its own component. The
// waits are condensed once per wave, and every component on one of their
// cycles becomes one, whose members finish together and inline one another
// only as beta steps. The waits are read in a fixed order (members by id,
// each member's in the order recorded, the built copies by name) and the
// cycles they close do not depend on it, so neither do the components.

#include "idr/Transforms/OptimizeScheduler.h"

#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Effects.h"

#include "mlir/IR/Remarks.h"
#include "mlir/IR/Threading.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/SCCIterator.h"
#include "llvm/ADT/STLExtras.h"

#include <deque>

using namespace mlir;

namespace idr::optimize {

namespace {

// What a function gives back, as the function holds it: each fact whose
// paths step through constructors' fields alone, a field a position. A
// natural's predecessor is no field laid out inline, so a fact through one
// stays the solve's and is not written.
void writeGivenBack(FuncOp fn, ArrayRef<identities::GivesBack> facts) {
  MLIRContext *ctx = fn.getContext();
  std::deque<SmallVector<std::uint32_t, 2>> fields;
  auto pathOf = [&](std::uint32_t index, const identities::Path &steps) -> std::optional<GivenBackPath> {
    SmallVector<std::uint32_t, 2> &out = fields.emplace_back();
    for (const identities::Step &step : steps)
      if (!idr::match(
              step,
              [&](const identities::Field &field) {
                out.push_back(field.index);
                return true;
              },
              [](identities::Predecessor) { return false; }))
        return std::nullopt;
    return GivenBackPath{index, out};
  };
  SmallVector<GivenBackEntry> entries;
  for (const identities::GivesBack &fact : facts) {
    std::optional<GivenBackPath> result = pathOf(fact.result, fact.resultPath);
    std::optional<GivenBackPath> argument = pathOf(fact.argument, fact.argumentPath);
    if (result && argument)
      entries.push_back(GivenBackEntry{*result, *argument});
  }
  llvm::sort(entries, [](const GivenBackEntry &a, const GivenBackEntry &b) {
    return std::pair(a.result.index, ArrayRef<std::uint32_t>(a.result.fields)) <
           std::pair(b.result.index, ArrayRef<std::uint32_t>(b.result.fields));
  });
  fn.setGivenBackAttr(entries.empty() ? GivenBackAttr() : GivenBackAttr::get(ctx, entries));
}

bool takenUp(const Phase &phase) {
  return idr::match(phase, [](Waiting) { return false; }, [](const auto &) { return true; });
}

bool isFinal(const Phase &phase) {
  return idr::match(phase, [](const Final &) { return true; }, [](const auto &) { return false; });
}

// The waits between components the condensation reads: a node per
// component leader met, an edge per wait not met, and a root reaching all.
struct WaitGraph {
  std::vector<unsigned> leaders;
  std::vector<std::vector<unsigned>> edges;
  unsigned root = 0;
};

struct WaitNode {
  const WaitGraph *graph;
  unsigned node;
  friend bool operator==(const WaitNode &a, const WaitNode &b) { return a.node == b.node; }
};

struct ToWaitNode {
  const WaitGraph *graph;
  WaitNode operator()(unsigned node) const { return {graph, node}; }
};

} // namespace
} // namespace idr::optimize

template <> struct llvm::GraphTraits<const idr::optimize::WaitGraph *> {
  using NodeRef = idr::optimize::WaitNode;
  using ChildIteratorType =
      llvm::mapped_iterator<std::vector<unsigned>::const_iterator, idr::optimize::ToWaitNode>;
  static NodeRef getEntryNode(const idr::optimize::WaitGraph *g) { return {g, g->root}; }
  static ChildIteratorType child_begin(NodeRef n) {
    return {n.graph->edges[n.node].begin(), idr::optimize::ToWaitNode{n.graph}};
  }
  static ChildIteratorType child_end(NodeRef n) {
    return {n.graph->edges[n.node].end(), idr::optimize::ToWaitNode{n.graph}};
  }
};

template <> struct llvm::DenseMapInfo<idr::optimize::WaitNode> {
  using NodeRef = idr::optimize::WaitNode;
  static NodeRef getEmptyKey() { return {nullptr, ~0u}; }
  static NodeRef getTombstoneKey() { return {nullptr, ~0u - 1}; }
  static unsigned getHashValue(const NodeRef &n) { return n.node; }
  static bool isEqual(const NodeRef &a, const NodeRef &b) { return a.node == b.node; }
};

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
    ArrayRef<FunctionId> ids = schedule.byComponent.find(leader)->second;
    if (schedule.unfinished.lookup(leader) != 0 ||
        isFinal(schedule.members.find(ids.front())->second.phase))
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
          [&](const Parked &parked) {
            if (member.unmet == 0)
              ready.push_back(Resume{id, parked.on});
          },
          [](const auto &) {});
    }
  }
}

// One turn per component, in leader order, its starters and resumed
// members in id order.
SmallVector<Turn, 0> Scheduler::gather(ArrayRef<Step> ready) {
  SmallVector<Turn, 0> wave;
  llvm::DenseMap<unsigned, unsigned> turnOf;
  for (const Step &step : ready) {
    FunctionId id = idr::match(step, [](Start start) { return start.member; },
                               [](const Resume &resume) { return resume.member; });
    unsigned leader = schedule.components.findLeader(id.index());
    auto [at, fresh] = turnOf.try_emplace(leader, wave.size());
    if (fresh)
      wave.emplace_back(leader);
    Turn &turn = wave[at->second];
    idr::match(
        step, [&](Start start) { turn.starters.push_back(start.member); },
        [&](const Resume &resume) { turn.resumed.push_back(resume.member); });
  }
  return wave;
}

// A copy goes into the program after its owner and its owner's copies
// whose names sort before its own, into the graph's editor with the calls
// its body makes, the analysis manager and the schedule, as a component of
// its own.
FunctionId Scheduler::insert(specialize::Node *made) {
  specialize::Built built = idr::match(
      made->phase, [](specialize::Built &b) { return std::move(b); },
      [](auto &) { return specialize::Built{}; });
  FuncOp fn = built.fn;
  FuncOp owner = schedule.function(made->origin);
  Block &body = *schedule.program.getBody();
  Block::iterator at = std::next(Block::iterator(owner.getOperation()));
  for (; at != body.end(); ++at) {
    auto next = dyn_cast<FuncOp>(*at);
    if (!next || !next.getSymName().starts_with(owner.getSymName()) ||
        next.getSymName().compare(fn.getSymName()) >= 0)
      break;
  }
  body.getOperations().insert(at, fn.getOperation());
  FunctionId id = schedule.graph.insert(fn);
  schedule.graph.setCallees(id, schedule.rowOf(fn));
  (void)am.nest(fn);
  nodes.place(*made, id);
  schedule.components.grow(id.index() + 1);
  Schedule::Member member{fn, made, made->origin, id};
  member.inherited = std::move(built.times);
  schedule.members.push_back(std::move(member));
  schedule.byName.try_emplace(fn.getSymNameAttr(), id);
  for (const solver::Call &call : schedule.graph.callees(id))
    if (!llvm::is_contained(schedule.members[call.callee.index()].callers, id))
      schedule.members[call.callee.index()].callers.push_back(id);
  unsigned leader = schedule.components.findLeader(id.index());
  schedule.byComponent[leader].push_back(id);
  check.push_back(leader);
  ++numMade;
  return id;
}

// `requester` waits on `target`, which it asked for or calls: nothing to
// wait on when the target is final or of its own component.
void Scheduler::want(FunctionId requester, FunctionId target) {
  if (isFinal(schedule.members[target.index()].phase) ||
      schedule.sameComponent(requester, target))
    return;
  Schedule::Member &member = schedule.members[requester.index()];
  if (llvm::is_contained(member.waitsOn, target))
    return;
  member.waitsOn.push_back(target);
  schedule.members[target.index()].waiters.push_back(requester);
  ++member.unmet;
  schedule.blocked.insert(requester.index());
}

// The component's summaries are published, its rows in the graph set, its
// unread parameters dropped, and each caller component's count of callees
// not final, and each wait on a member, counted down.
void Scheduler::finalize(unsigned component) {
  SmallVector<FunctionId> ids(schedule.byComponent.find(component)->second);
  dropUnread(schedule, ids);
  // The rows: one join over the component, every call of a member taking
  // it; and what each member gives back over the parameters it kept, its
  // callees' read as their components published them, which later turns
  // read.
  SmallVector<solver::Member> members;
  for (FunctionId id : ids)
    members.push_back(solver::Member{id, schedule.function(id)});
  rows::writeComponent(members, schedule.graph);
  std::vector<identities::Facts> given =
      identities::givesBackOf(schedule.graph, members, [&](FunctionId callee) {
        return schedule.callees.of(FlatSymbolRefAttr::get(schedule.symbolOf(callee)));
      });
  for (auto [id, facts] : llvm::zip_equal(ids, given)) {
    writeGivenBack(schedule.function(id), facts);
    schedule.callees.publish(id, std::move(facts));
  }
  for (FunctionId id : ids) {
    Schedule::Member &member = schedule.members[id.index()];
    Solved solved = idr::match(member.phase, [](Done &done) { return std::move(done.solved); },
                               [](auto &) { return Solved{}; });
    member.phase = Final{Summary{std::move(solved.times), returnedConstants(member.fn),
                                 inlining::bodyOf(member.fn)}};
    schedule.graph.setCallees(id, schedule.rowOf(member.fn));
  }
  // A copy whose final component has no cycle terminates as its calls do:
  // nothing of its own loops.
  if (ids.size() == 1 && schedule.members[ids.front().index()].node &&
      llvm::none_of(schedule.graph.callees(ids.front()),
                    [&](const solver::Call &call) { return call.callee == ids.front(); }))
    termination::markAcyclic(schedule.function(ids.front()));
  llvm::SmallDenseSet<unsigned, 8> callers;
  for (FunctionId id : ids)
    for (FunctionId caller : schedule.callersOf(id))
      if (unsigned leader = schedule.components.findLeader(caller.index()); leader != component)
        callers.insert(leader);
  for (unsigned leader : callers)
    if (--schedule.unfinished[leader] == 0)
      check.push_back(leader);
  for (FunctionId id : ids)
    for (FunctionId waiter : schedule.members[id.index()].waiters) {
      Schedule::Member &member = schedule.members[waiter.index()];
      if (member.unmet != 0 && --member.unmet == 0) {
        schedule.blocked.erase(waiter.index());
        check.push_back(schedule.components.findLeader(waiter.index()));
      }
    }
}

void Scheduler::settle(MutableArrayRef<Turn> wave) {
  SmallVector<specialize::Node *> built;
  for (Turn &turn : wave)
    llvm::append_range(built, turn.built);
  // Which turn built a copy changes nothing; the name fixes the order.
  llvm::sort(built, [](specialize::Node *lhs, specialize::Node *rhs) {
    return lhs->name.getValue() < rhs->name.getValue();
  });
  SmallVector<FunctionId> placed;
  for (specialize::Node *made : built)
    placed.push_back(insert(made));
  for (Turn &turn : wave)
    if (turn.ends == Turn::Ends::Yes)
      finalize(turn.component);

  // The waits of the wave: each parked member on the copies of its batch,
  // each placed copy on what it calls.
  for (Turn &turn : wave) {
    for (auto &[requester, asked] : turn.parked)
      for (specialize::Node *made : asked)
        idr::match(
            made->phase, [&](const specialize::Placed &at) { want(requester, at.id); },
            [](const auto &) {});
    check.push_back(turn.component);
  }
  for (FunctionId id : placed)
    for (const solver::Call &call : schedule.graph.callees(id))
      want(id, call.callee);

  // The cycles the waits close, condensed once: every component of a
  // cycle joins one, and the waits inside it are met.
  WaitGraph waits;
  llvm::DenseMap<unsigned, unsigned> nodeOf;
  auto nodeFor = [&](unsigned leader) {
    auto [at, fresh] = nodeOf.try_emplace(leader, waits.leaders.size());
    if (fresh) {
      waits.leaders.push_back(leader);
      waits.edges.emplace_back();
    }
    return at->second;
  };
  SmallVector<unsigned> blocked(schedule.blocked.begin(), schedule.blocked.end());
  llvm::sort(blocked);
  for (unsigned raw : blocked) {
    FunctionId id = schedule.members[raw].self;
    unsigned from = nodeFor(schedule.components.findLeader(id.index()));
    for (FunctionId target : schedule.members[id.index()].waitsOn)
      if (!isFinal(schedule.members[target.index()].phase) &&
          !schedule.sameComponent(id, target))
        waits.edges[from].push_back(nodeFor(schedule.components.findLeader(target.index())));
  }
  waits.root = waits.leaders.size();
  waits.leaders.push_back(~0u);
  waits.edges.emplace_back();
  for (unsigned n = 0; n < waits.root; ++n)
    waits.edges[waits.root].push_back(n);
  SmallVector<unsigned> merged;
  for (auto scc = llvm::scc_begin(static_cast<const WaitGraph *>(&waits)); !scc.isAtEnd(); ++scc) {
    if (scc->size() < 2)
      continue;
    SmallVector<unsigned> parts =
        llvm::map_to_vector(*scc, [&](const WaitNode &node) { return waits.leaders[node.node]; });
    llvm::sort(parts);
    SmallVector<FunctionId> joined;
    for (unsigned part : parts) {
      llvm::append_range(joined, schedule.byComponent[part]);
      schedule.byComponent.erase(part);
      schedule.unfinished.erase(part);
    }
    for (unsigned part : llvm::drop_begin(parts))
      schedule.components.join(parts.front(), part);
    unsigned leader = schedule.components.findLeader(parts.front());
    llvm::sort(joined);
    schedule.byComponent[leader] = std::move(joined);
    merged.push_back(leader);
  }
  // A merged component's members recount what they wait on, and its
  // callees not final are those of every member's calls.
  for (unsigned leader : merged) {
    llvm::SmallDenseSet<unsigned, 8> callees;
    for (FunctionId id : schedule.byComponent[leader]) {
      Schedule::Member &member = schedule.members[id.index()];
      member.unmet = static_cast<unsigned>(llvm::count_if(member.waitsOn, [&](FunctionId target) {
        return !isFinal(schedule.members[target.index()].phase) &&
               !schedule.sameComponent(id, target);
      }));
      if (member.unmet == 0)
        schedule.blocked.erase(id.index());
      for (const solver::Call &call : schedule.graph.callees(id))
        if (unsigned theirs = schedule.components.findLeader(call.callee.index());
            theirs != leader && !isFinal(schedule.members[call.callee.index()].phase))
          callees.insert(theirs);
    }
    schedule.unfinished[leader] = callees.size();
    check.push_back(leader);
  }
}

LogicalResult Scheduler::run() {
  MLIRContext *context = schedule.program.getContext();
  for (const auto &entry : schedule.byComponent)
    check.push_back(entry.first);
  SmallVector<Step> ready;
  enable(ready);
  while (!ready.empty()) {
    SmallVector<Turn, 0> wave = gather(ready);
    ready.clear();
    // The turns are disjoint, so the output is theirs in any order; the
    // context runs them one after another when its threading is off, as it
    // is while an action handler counts.
    if (failed(failableParallelForEach(context, wave, [&](Turn &work) { return turn(work); })))
      return failure();
    settle(wave);
    if (remark::detail::InFlightRemark progress = remark::analysis(
            schedule.program.getLoc(), remark::RemarkOpts::name("progress").category("idr-optimize")))
      progress << remark::metric("functions", schedule.members.size())
               << remark::metric("made", numMade);
    enable(ready);
  }
  for (auto &[id, member] : schedule.members)
    if (!isFinal(member.phase))
      return member.fn.emitError() << "internal error: idr-optimize: the schedule stopped with @"
                                   << member.fn.getSymName() << " not final";
  return success();
}

} // namespace idr::optimize
