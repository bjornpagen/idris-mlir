// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The decide step's decision for one function, once it is read: which
// cells and calls must be counted, every run's lifetime (its source, the
// ops it spans, what lives in it), and what a copy puts into its lifetime
// parameter. One marking over the function's values per round, never a set
// per value and never the whole program's graph.

#include "idr/Transforms/Lifetimes/Plan.h"

#include "idr/IR/Grades.h"
#include "idr/IR/Verify.h"
#include "idr/Support/Changed.h"

#include "llvm/ADT/STLExtras.h"

#include <cstdint>

using namespace mlir;
using namespace idr;
using namespace idr::lifetimes::decide;

namespace {

// The calls continuing on a frame that a lifetime's extent holds: none;
// each in the block of the lifetime's region, around which frames split
// it; or one inside another op there (a match, a loop), around which they
// cannot, so the run stays counted, as it would with no lifetime.
enum class FramedCalls : std::uint8_t { None, InBlock, Nested };

} // namespace

Plan Planner::plan() {
  readAll();
  flow.emplace(std::move(flowEdges).finish());
  Csr<Values> linked = std::move(linkedEdges).finish();
  BitSet<Node> reachesReturn = marked<Backward>(*flow, returned);
  // What a copy returns is its parameter's.
  auto putHere = [&](Node n) { return reading == Reading::Put && reachesReturn.test(n); };

  footprint::Vector<Fate> siteFates(sites.size(), Fate::Open), callFates(calls.size(), Fate::Open);
  // On a component that runs calls on frames, a member's call of a member
  // is one of a copy's puts, given the parameter the copies share, or
  // counted: a lifetime this function opens, given to a member, would be a
  // second arrangement of lifetimes on the component's stack.
  if (framing == Framing::Framed)
    for (auto [at, call] : llvm::enumerate(calls))
      if (graph.sccOf(call.callee) == graph.sccOf(self) && !putHere(call.results.front()))
        callFates[at] = Fate::Counted;
  // One round: the cells and calls counted so far, and those they make
  // counted, then a lifetime for every run; nothing when a run's decision
  // made another cell or call counted.
  auto round = [&]() -> std::optional<Plan> {
    footprint::Vector<Node> seeds(fixed.begin(), fixed.end());
    for (auto [at, site] : llvm::enumerate(sites))
      if (siteFates[at] == Fate::Counted)
        seeds.push_back(site.box);
    for (auto [at, call] : llvm::enumerate(calls))
      if (callFates[at] == Fate::Counted)
        llvm::append_range(seeds, call.results);
    BitSet<Node> mustCount = marked<Forward>(linked, seeds);
    for (auto [at, site] : llvm::enumerate(sites))
      if (mustCount.test(site.box))
        siteFates[at] = Fate::Counted;
    for (auto [at, call] : llvm::enumerate(calls))
      if (llvm::any_of(call.results, [&](Node result) { return mustCount.test(result); }))
        callFates[at] = Fate::Counted;

    // Each run's cells and calls that stay in this function.
    footprint::Vector<Draft> drafts;
    auto draftOf = [&](const RunAt &run) -> Draft & {
      auto found = llvm::find_if(drafts, [&](const Draft &draft) { return draft.run == run; });
      if (found != drafts.end())
        return *found;
      drafts.push_back({run, {}, {}});
      return drafts.back();
    };
    Draft putDraft{std::nullopt, {}, {}};
    for (auto [at, site] : llvm::enumerate(sites))
      if (siteFates[at] == Fate::Open)
        (putHere(site.box) ? putDraft : draftOf(site.run)).sites.push_back(at);
    for (auto [at, call] : llvm::enumerate(calls))
      if (callFates[at] == Fate::Open)
        (putHere(call.results.front()) ? putDraft : draftOf(call.run)).calls.push_back(at);
    // Every run before the runs inside it: the body first, then by where
    // each run's op stands in the order, which puts an op before the ops
    // inside it.
    llvm::stable_sort(drafts, [](const Draft &a, const Draft &b) { return a.run < b.run; });

    BodyOpener opener = putDraft.sites.empty() && putDraft.calls.empty() ? BodyOpener::Allowed
                                                                        : BodyOpener::Refused;
    Plan made;
    Changed demoted = Changed::No;
    for (const Draft &draft : drafts) {
      std::optional<Group> group = decide(draft, opener, siteFates, callFates);
      if (group)
        made.groups.push_back(std::move(*group));
      else
        demoted = Changed::Yes;
    }
    if (demoted == Changed::Yes)
      return std::nullopt;
    if (reading == Reading::Put)
      made.put = putForm(putDraft);
    return made;
  };
  // Each round either makes a cell or a call counted for good or decides
  // every run: the rounds end after one per cell and call at most, with
  // one where nothing more is counted.
  std::optional<Plan> decided = round();
  while (!decided)
    decided = round();
  return std::move(*decided);
}

// Whether a lifetime may span the ops of `block` from `first` to `last`: it
// holds no call in tail position, whose return would follow the lifetime's
// end, and no jump to a join point outside it, which no lifetime lets
// through.
bool Planner::spannable(Block &block, OpAt first, OpAt last) const {
  Operation *firstOp = order.op(first);
  Operation *lastOp = order.op(last);
  auto inside = [&](Operation *op) {
    Operation *top = block.findAncestorOpInBlock(*op);
    return top && !top->isBeforeInBlock(firstOp) && !lastOp->isBeforeInBlock(top);
  };
  for (Operation *op : order.span(first, last)) {
    if (auto call = dyn_cast<CallOp>(op); call && call.getTailKind() != TailKind::nontail)
      return false;
    for (Value operand : op->getOperands())
      if (isa<mlir::TokenType>(operand.getType()))
        if (auto token = dyn_cast<BlockArgument>(operand);
            !token || !inside(token.getOwner()->getParentOp()))
          return false;
  }
  return true;
}

// One run's lifetime, or none when a cell or a call of it is counted.
std::optional<Group> Planner::decide(const Draft &draft, BodyOpener opener,
                                     footprint::Vector<Fate> &siteFates,
                                     footprint::Vector<Fate> &callFates) {
  Region &region =
      draft.run ? order.op(draft.run->first)->getRegion(draft.run->second) : fn.getBody();
  Block &block = region.front();
  OpAt start = draft.run ? order.firstIn(draft.run->first, draft.run->second)
                         : order.firstIn(order.root(), 0);
  bool body = !draft.run;
  footprint::Vector<Node> roots;
  for (unsigned at : draft.sites)
    roots.push_back(sites[at].box);
  for (unsigned at : draft.calls)
    llvm::append_range(roots, calls[at].results);
  BitSet<Node> reach = marked<Forward>(*flow, roots);

  // The ops of the run the lifetime spans: from its first cell or call to
  // the last use of a value that lives in it, each seen at the run's top,
  // in the block's own order.
  Operation *firstOp = nullptr;
  Operation *lastOp = nullptr;
  auto widen = [&](Operation *op) {
    Operation *top = block.findAncestorOpInBlock(*op);
    if (!top)
      return;
    if (!firstOp || top->isBeforeInBlock(firstOp))
      firstOp = top;
    if (!lastOp || lastOp->isBeforeInBlock(top))
      lastOp = top;
  };
  for (unsigned at : draft.sites)
    widen(order.op(sites[at].source));
  for (unsigned at : draft.calls)
    widen(order.op(calls[at].op));
  for (Node n : count.ids())
    if (reach.test(n))
      for (Operation *user : valueOf(n).getUsers())
        widen(user);
  auto [first, last] = order.positions(start, block, firstOp, lastOp);
  FramedCalls framedCalls = FramedCalls::None;
  for (OpAt call : framed)
    if (order.within(call, first, last))
      framedCalls = order.op(call)->getBlock() == &block && framedCalls != FramedCalls::Nested
                        ? FramedCalls::InBlock
                        : FramedCalls::Nested;

  Group group;
  group.run = draft.run;
  bool allRooms = llvm::all_of(draft.calls, [&](unsigned at) {
    return copies[calls[at].callee]->modes.contains(CopyMode::Room);
  });
  if (framedCalls != FramedCalls::None) {
    group.source = Opening::Cursor;
    group.cells = Cells::Bumped;
  } else if (draft.calls.empty()) {
    group.source = body && framed.empty() ? Opening::Activation : Opening::NoMemory;
  } else if (allRooms) {
    group.source = Opening::Block;
  } else {
    group.source = body && fn.isRoot() ? Opening::Home : Opening::Cursor;
  }
  if (group.source != Opening::Activation) {
    group.extent = std::pair(first, last);
    if ((body && opener == BodyOpener::Refused) || framedCalls == FramedCalls::Nested ||
        !spannable(block, first, last)) {
      for (unsigned at : draft.sites)
        siteFates[at] = Fate::Counted;
      for (unsigned at : draft.calls)
        callFates[at] = Fate::Counted;
      return std::nullopt;
    }
  }

  // A cursor's or a home's call stands at the top of its region, and what
  // it gives is used again after every allocation that follows it there.
  if (group.source == Opening::Cursor || group.source == Opening::Home) {
    bool demoted = false;
    for (unsigned at : draft.calls) {
      const Call &call = calls[at];
      bool holds = copies[call.callee]->modes.contains(modeOf(group.source)) &&
                   order.op(call.op)->getBlock() == &block &&
                   llvm::all_of(call.results, [&](Node result) {
                     return verify::usedAfterEveryAllocation(valueOf(result), lastOp);
                   });
      if (!holds) {
        callFates[at] = Fate::Counted;
        demoted = true;
      }
    }
    if (demoted)
      return std::nullopt;
  }

  for (unsigned at : draft.sites)
    group.sites.push_back(sites[at].source);
  for (unsigned at : draft.calls)
    group.calls.push_back({calls[at].op, calls[at].callee});
  for (Node n : count.ids())
    if (reach.test(n))
      group.scoped.push_back(n);
  return group;
}

// What a copy puts into its lifetime parameter: the cells and calls whose
// values reach what it returns at the positions its copies may put. A
// room's copy puts each cell once and calls only rooms' copies outside its
// own component; a cursor's or a home's takes every value it makes there
// into what it gives back on every path, and calls only copies that do.
std::optional<PutForm> Planner::putForm(const Draft &draft) {
  auto ret = dyn_cast<ReturnOp>(fn.getBody().front().getTerminator());
  if (!ret || (draft.sites.empty() && draft.calls.empty()))
    return std::nullopt;
  footprint::Vector<Node> roots;
  for (unsigned at : draft.sites)
    roots.push_back(sites[at].box);
  for (unsigned at : draft.calls)
    llvm::append_range(roots, calls[at].results);
  BitSet<Node> reach = marked<Forward>(*flow, roots);

  PutForm form;
  for (auto [index, operand] : llvm::enumerate(ret.getOperands()))
    if (holdsLiving(operand.getType()) && reach.test(node(operand)))
      form.results.push_back(static_cast<unsigned>(index));
  if (form.results.empty())
    return std::nullopt;

  auto lives = [&](Value value) { return reach.test(node(value)); };
  auto returnedHere = [&](unsigned result) { return llvm::is_contained(form.results, result); };
  bool bounded = llvm::all_of(draft.calls, [&](unsigned at) {
    FunctionId callee = calls[at].callee;
    return graph.sccOf(callee) != graph.sccOf(self) &&
           copies[callee]->modes.contains(CopyMode::Room);
  });
  bool kept = llvm::all_of(draft.calls,
                           [&](unsigned at) {
                             return copies[calls[at].callee]->modes.contains(CopyMode::Cursor);
                           }) &&
              llvm::all_of(count.ids(), [&](Node n) {
                Value value = valueOf(n);
                return !reach.test(n) || !isa<OpResult>(value) ||
                       verify::takenIntoResult(value, lives, returnedHere);
              });
  // A tail call lowers to its caller's own return, which gives back the
  // caller's cursors: a cursor's copy gives its one cursor, as its first,
  // to every function it tail calls, so each such call is one of its puts,
  // to the copy that takes that cursor.
  bool tailsPut = llvm::all_of(tails, [&](OpAt tail) {
    return llvm::any_of(draft.calls, [&](unsigned at) { return calls[at].op == tail; });
  });
  form.modes = copies[self]->modes;
  if (!bounded)
    form.modes = form.modes.without(CopyMode::Room);
  if (!kept)
    form.modes = form.modes.without(CopyMode::Cursor).without(CopyMode::Home);
  if (!tailsPut)
    form.modes = form.modes.without(CopyMode::Cursor);
  if (form.modes.empty())
    return std::nullopt;

  for (unsigned at : draft.sites)
    form.sites.push_back(sites[at].source);
  for (unsigned at : draft.calls)
    form.calls.push_back({calls[at].op, calls[at].callee});
  for (Node n : count.ids())
    if (reach.test(n))
      form.scoped.push_back(n);
  return form;
}
