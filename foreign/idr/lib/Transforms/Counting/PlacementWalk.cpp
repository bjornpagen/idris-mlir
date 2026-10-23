// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-rc-place's walk (Placement.h): each function's regions walked in
// reverse, the set of values some later use needs as the walk's one state.
// A region op that enters one of its regions once per run moves what its
// regions need into them, each region dropping at its head what a sibling
// needs and it does not; one that may run a region any number of times, or
// none, holds what its regions read across it, save a value used once that
// the region it runs first and alone reads (a loop's body), which moves in
// there as into a region run once; and one whose region binds a lifetime
// holds what is lent to upstream's ops under it, which outlives the
// lifetime. A terminator's successors say what is needed where it
// leaves. The walk's stacks are on the heap, so a nesting of any depth
// costs no native stack.
#include "idr/Transforms/Counting/Placement.h"

#include "idr/IR/Effects/Consumption.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"

#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::counting::placement {

namespace {

// The region a region op runs first and alone, once per run, before any of
// its regions may run again: the one region it enters from itself, where it
// never goes straight to its results and that region never runs again (a
// loop's body, which jumps into the loop's join regions). None for an op
// that enters several, may skip them, or enters one that repeats.
Region *runFirst(Operation *op) {
  auto branch = dyn_cast<RegionBranchOpInterface>(op);
  if (!branch)
    return nullptr;
  llvm::SmallVector<RegionSuccessor> entries;
  branch.getSuccessorRegions(RegionBranchPoint::parent(), entries);
  if (entries.size() != 1 || entries.front().isOperation())
    return nullptr;
  Region *first = entries.front().getSuccessor();
  return branch.isRepetitiveRegion(first->getRegionNumber()) ? nullptr : first;
}

} // namespace

// The frame of a region op on the walk's stack of them: the op whose
// results a yield gives or whose region a jump enters, the walk's own
// parent or an op around it.
OpWalk *Placement::frameOf(Operation *op) {
  for (OpWalk &walk : llvm::reverse(ops))
    if (walk.op == op)
      return &walk;
  return nullptr;
}

// What a successor of a terminator needs live: after the op whose results it
// gives, with what that op holds across its regions; or at the head of the
// region it enters, which an op that runs its regions once has walked before
// the region that jumps there, and an op that repeats holds as it holds
// after itself.
State Placement::successorState(const RegionSuccessor &successor, Operation *terminator) {
  Operation *target = successor.isOperation() ? successor.getSuccessorOp()
                                              : successor.getSuccessor()->getParentOp();
  OpWalk *walk = frameOf(target);
  if (!walk) {
    fail(terminator, "counting meets a successor outside the regions it walks");
    return State{llvm::BitVector(count.value()), Ahead::Allocation};
  }
  if (successor.isOperation() || walk->runs == Runs::Repeats) {
    State state = walk->after;
    state.live |= walk->held;
    return state;
  }
  std::optional<State> &entry = walk->entries[successor.getSuccessor()->getRegionNumber()];
  if (!entry) {
    fail(terminator, "a jump reaches a region counting has not walked");
    return State{llvm::BitVector(count.value()), Ahead::Allocation};
  }
  return *entry;
}

// The operands `op` consumes: a return's move to the caller, a terminator's
// forwarded ones to its successors, a region op's entry operands into the
// regions they enter, a counted operand an op gives back as its result (a
// cast, a share, a loan, whose result then holds the reference); any other
// operand consumes as its op declares. A move on takes a reference over
// only from an operand its hold says is counted: a view moved on holds
// none, and what receives it is a view too, so forwarding one into a
// region and yielding it out consumes nothing.
llvm::SmallBitVector Placement::consumedBy(Operation *op) {
  llvm::SmallBitVector consumed(op->getNumOperands());
  auto moves = [&](unsigned at) {
    if (freedBy(op->getOperand(at).getType(), Release::Counted))
      consumed.set(at);
  };
  auto mark = [&](OperandRange forwarded) {
    if (forwarded.empty())
      return;
    unsigned first = forwarded.getBeginOperandIndex();
    for (unsigned at = first, end = first + static_cast<unsigned>(forwarded.size()); at < end; ++at)
      moves(at);
  };
  if (op->hasTrait<OpTrait::IsTerminator>() && leavesOf(op) == Leaves::Frame) {
    for (unsigned at = 0, end = op->getNumOperands(); at < end; ++at)
      moves(at);
    return consumed;
  }
  if (auto terminator = dyn_cast<RegionBranchTerminatorOpInterface>(op)) {
    llvm::SmallVector<Attribute> constants(op->getNumOperands());
    llvm::SmallVector<RegionSuccessor> successors;
    terminator.getSuccessorRegions(constants, successors);
    for (const RegionSuccessor &successor : successors)
      mark(terminator.getSuccessorOperands(successor));
  }
  if (auto branch = dyn_cast<RegionBranchOpInterface>(op)) {
    llvm::SmallVector<RegionSuccessor> entries;
    branch.getSuccessorRegions(RegionBranchPoint::parent(), entries);
    for (const RegionSuccessor &entry : entries)
      mark(branch.getEntrySuccessorOperands(entry));
  }
  if (givesOperandBack(op) && freedBy(op->getOperand(0).getType(), Release::Counted))
    consumed.set(0);
  for (OpOperand &operand : op->getOpOperands())
    if (!consumed.test(operand.getOperandNumber()) && effects::consumes(operand))
      consumed.set(operand.getOperandNumber());
  return consumed;
}

// Whether a counted value still holds its reference at `op`: some later use
// needs it, or `op` uses it.
bool Placement::aliveAt(ValueId owner, Operation *op, const State &state) const {
  return state.live.test(owner.index()) ||
         llvm::any_of(op->getOperands(), [&](Value operand) { return idOf(operand) == owner; });
}

// The counted values defined outside `op` that its regions use, a part's
// owner with the part: what an op that may run its regions many times holds
// across them. A value used once whose use lies in `first`, the region the
// op runs first and alone, is not held: that region runs once, before
// anything repeats, so its one use there moves it in, as a region an op
// enters once takes what it needs, and nothing duplicates it.
llvm::BitVector Placement::heldBy(Operation *op, Region *first) const {
  llvm::BitVector held(count.value());
  op->walk([&](Operation *inner) {
    if (inner == op)
      return;
    for (Value operand : inner->getOperands()) {
      if (op->isAncestor(operand.getParentBlock()->getParentOp()))
        continue;
      if (first && first->isAncestor(inner->getParentRegion()) &&
          usesOf(operand.getType()) == Uses::Once)
        continue;
      ValueId id = idOf(operand);
      if (roles[id] == Role::Owned)
        held.set(id.index());
      else if (roles[id] == Role::Part)
        held.set(ownerOf[id]->index());
    }
  });
  return held;
}

// The counted owners lent to upstream's ops under a lifetime one of `op`'s
// regions binds: a loan's uses are reads of a part while its owner lives,
// and the owner outlives the lifetime, so `op` holds it across its regions
// and it dies, if nothing needs it after, as `op` ends.
void Placement::holdLent(Operation *op, llvm::BitVector &held) const {
  if (lent.empty())
    return;
  auto byExtent = [](const std::pair<std::uint32_t, ValueId> &row, std::uint32_t extent) {
    return row.first < extent;
  };
  for (Region &region : op->getRegions()) {
    if (region.empty())
      continue;
    for (BlockArgument arg : region.front().getArguments()) {
      std::uint32_t extent = idOf(arg).index();
      for (auto at = llvm::lower_bound(lent, extent, byExtent);
           at != lent.end() && at->first == extent; ++at)
        held.set(at->second.index());
    }
  }
}

void Placement::stepBlock(BlockWalk &walk) {
  if (!walk.next) {
    finishBlock(walk);
    return;
  }
  Operation *op = walk.next;
  walk.next = op->getPrevNode();
  State &state = walk.state;
  if (op->hasTrait<OpTrait::IsTerminator>()) {
    enterTerminator(op, state);
    llvm::SmallBitVector consumed = consumedBy(op);
    operandDeaths(op, consumed, state, nullptr, nullptr);
    useOperands(op, state, consumed, nullptr);
    return;
  }
  // A result nothing needs dies where it is made; an element that takes its
  // reference where it is read takes it there only if something needs it,
  // and one nothing needs was never given one.
  for (Value result : op->getResults()) {
    ValueId id = idOf(result);
    if (roles[id] != Role::Owned)
      continue;
    bool needed = state.live.test(id.index());
    if (takesWhereRead.test(id.index())) {
      if (needed)
        elementDups.push_back(id);
      continue;
    }
    if (!needed)
      death(id, Where::past(op), Death::Reading, state);
  }
  for (Value result : op->getResults())
    state.live.reset(idOf(result).index());
  if (op->getNumRegions() == 0) {
    llvm::SmallBitVector consumed = consumedBy(op);
    operandDeaths(op, consumed, state, nullptr, nullptr);
    useOperands(op, state, consumed, nullptr);
    return;
  }
  // A region op: its regions are walked from what is live after it. A part
  // still needed after it is pinned: no region supplies it.
  OpWalk regions{op, runsOf(op), runFirst(op), state, op->getNumRegions(), {},
                 llvm::BitVector(count.value()), llvm::BitVector(count.value())};
  regions.entries.resize(op->getNumRegions());
  if (regions.runs == Runs::Repeats)
    regions.held = heldBy(op, regions.first);
  holdLent(op, regions.held);
  for (unsigned at : regions.after.live.set_bits())
    if (roles[idAt(at)] == Role::Part && !pinned.test(at)) {
      regions.pinnedHere.set(at);
      pinned.set(at);
    }
  ops.push_back(std::move(regions));
}

void Placement::stepOp(OpWalk &walk) {
  if (walk.remaining > 0) {
    unsigned index = --walk.remaining;
    Region &region = walk.op->getRegion(index);
    if (region.empty())
      return;
    Block &entry = region.front();
    blocks.push_back(BlockWalk{&entry, &entry.back(), State{llvm::BitVector(count.value()), Ahead::Allocation}, index});
    return;
  }
  State before = finishOp(walk);
  OpWalk finished = std::move(walk);
  pinned.reset(finished.pinnedHere);
  ops.pop_back();
  State &state = blocks.back().state;
  state = std::move(before);
  // The op's own operands, read or moved as it begins: a value its regions
  // need is live into it already.
  llvm::BitVector inside = state.live;
  llvm::SmallBitVector consumed = consumedBy(finished.op);
  operandDeaths(finished.op, consumed, state, &inside, &finished.after);
  useOperands(finished.op, state, consumed, &inside);
}

void Placement::finishBlock(BlockWalk &walking) {
  BlockWalk walk = std::move(walking);
  blocks.pop_back();
  // The block's arguments are made at its start: one nothing needs dies
  // there.
  for (BlockArgument arg : walk.block->getArguments()) {
    ValueId id = idOf(arg);
    if (roles[id] == Role::Owned && !walk.state.live.test(id.index()))
      death(id, Where::atStart(*walk.block), Death::Reading, walk.state);
    walk.state.live.reset(id.index());
  }
  if (ops.empty())
    return;
  ops.back().entries[walk.region] = std::move(walk.state);
}

// What is live as a region op begins, its regions walked: for an op that
// enters one region once, what any region it enters needs, each region
// dropping at its head (or taking apart, where a part of it lives on) what a
// sibling needs and it does not; for one that may repeat, what it holds
// across its regions, what is live after it and what the region it runs
// first moves in. The parts pinned at the op take their references before
// it, where their owners still live.
State Placement::finishOp(OpWalk &walk) {
  Operation *op = walk.op;
  State before{llvm::BitVector(count.value()), walk.after.ahead};
  if (walk.runs == Runs::Repeats) {
    before.live = walk.after.live;
    before.live |= walk.held;
    // And what the region it runs first takes in: beyond what the op holds,
    // the values used once that it moves in.
    if (walk.first)
      if (const std::optional<State> &entry = walk.entries[walk.first->getRegionNumber()])
        before.live |= entry->live;
  } else {
    auto branch = cast<RegionBranchOpInterface>(op);
    llvm::SmallVector<RegionSuccessor> entries;
    branch.getSuccessorRegions(RegionBranchPoint::parent(), entries);
    // The counted values some entered region needs, before any head acts.
    llvm::BitVector owners(count.value());
    for (const RegionSuccessor &entry : entries)
      if (const std::optional<State> &state = walk.entries[entry.getSuccessor()->getRegionNumber()])
        owners |= state->live;
    for (unsigned at : owners.set_bits())
      if (roles[idAt(at)] != Role::Owned)
        owners.reset(at);
    before.ahead = Ahead::End;
    for (const RegionSuccessor &entry : entries) {
      Region *region = entry.getSuccessor();
      std::optional<State> &state = walk.entries[region->getRegionNumber()];
      if (!state)
        continue;
      llvm::BitVector dead = owners;
      dead.reset(state->live);
      for (unsigned at : dead.set_bits())
        death(idAt(at), Where::atStart(region->front()), Death::Reading, *state);
      before.live |= state->live;
      if (state->ahead == Ahead::Allocation)
        before.ahead = Ahead::Allocation;
    }
    before.live |= owners;
  }
  for (unsigned at : walk.pinnedHere.set_bits()) {
    ValueId part = idAt(at);
    ValueId owner = *ownerOf[part];
    bool ownerLives = before.live.test(owner.index()) ||
                      llvm::any_of(op->getOperands(), [&](Value operand) { return idOf(operand) == owner; });
    if (!ownerLives)
      continue;
    dupSupplies.push_back({Where::before(op), part});
    before.live.reset(at);
  }
  // A value an op holds across its regions (one that repeats holds what
  // they read, and any holds what is lent under a lifetime it binds), and
  // nothing needs after it, dies as the op ends.
  State after = walk.after;
  after.live.reset(walk.pinnedHere);
  llvm::BitVector dying = walk.held;
  dying.reset(walk.after.live);
  for (unsigned at : dying.set_bits())
    if (roles[idAt(at)] == Role::Owned)
      death(idAt(at), Where::past(op), Death::Reading, after);
  return before;
}

// How a terminator leaves: out of the function, nothing live and the caller
// ahead; out of the process, nothing live and only the end ahead; or to its
// successors, whatever each of them needs.
void Placement::enterTerminator(Operation *terminator, State &state) {
  state.live.reset();
  switch (leavesOf(terminator)) {
  case Leaves::Frame:
    state.ahead = Ahead::Allocation;
    return;
  case Leaves::Process:
    state.ahead = Ahead::End;
    return;
  case Leaves::Successors:
    break;
  }
  auto branching = cast<RegionBranchTerminatorOpInterface>(terminator);
  llvm::SmallVector<Attribute> constants(terminator->getNumOperands());
  llvm::SmallVector<RegionSuccessor> successors;
  branching.getSuccessorRegions(constants, successors);
  state.ahead = Ahead::End;
  for (const RegionSuccessor &successor : successors) {
    State next = successorState(successor, terminator);
    state.live |= next.live;
    if (next.ahead == Ahead::Allocation)
      state.ahead = Ahead::Allocation;
  }
}

} // namespace idr::counting::placement
