// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-rc-place's walk (Placement.h): each function's regions walked in
// reverse, the set of values some later use needs as the walk's one state.
// A region op that enters one of its regions once per run moves what its
// regions need into them, each region dropping at its head what a sibling
// needs and it does not; one that may run a region any number of times, or
// none, holds what its regions read across it. A terminator's successors
// say what is needed where it leaves. The walk's stack is on the heap, so
// a nesting of any depth costs no native stack.
#include "idr/Transforms/Counting/Placement.h"

#include "idr/IR/Effects/Query.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"

#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::counting::placement {

// The frame of a region op on the walk's stack: the op whose results a
// yield gives or whose region a jump enters, the walk's own parent or an op
// around it.
OpWalk *Placement::frameOf(Operation *op) {
  for (Frame &frame : llvm::reverse(stack))
    if (auto *walk = std::get_if<OpWalk>(&frame); walk && walk->op == op)
      return walk;
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
// operand consumes as its op declares.
llvm::SmallBitVector Placement::consumedBy(Operation *op) {
  llvm::SmallBitVector consumed(op->getNumOperands());
  auto mark = [&](OperandRange forwarded) {
    if (forwarded.empty())
      return;
    unsigned first = forwarded.getBeginOperandIndex();
    for (unsigned at = first, end = first + static_cast<unsigned>(forwarded.size()); at < end; ++at)
      consumed.set(at);
  };
  if (op->hasTrait<OpTrait::IsTerminator>() && leavesOf(op) == Leaves::Frame) {
    consumed.set();
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
  if (givesOperandBack(op) && countsOf(op->getOperand(0).getType()) == Counts::Counted)
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
// across them.
llvm::BitVector Placement::heldBy(Operation *op) const {
  llvm::BitVector held(count.value());
  op->walk([&](Operation *inner) {
    if (inner == op)
      return;
    for (Value operand : inner->getOperands()) {
      if (op->isAncestor(operand.getParentBlock()->getParentOp()))
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

void Placement::stepBlock() {
  auto &walk = std::get<BlockWalk>(stack.back());
  if (!walk.next) {
    finishBlock();
    return;
  }
  Operation *op = walk.next;
  walk.next = op->getPrevNode();
  if (op->hasTrait<OpTrait::IsTerminator>()) {
    enterTerminator(op, walk.state);
    llvm::SmallBitVector consumed = consumedBy(op);
    State &state = std::get<BlockWalk>(stack.back()).state;
    operandDeaths(op, consumed, state, nullptr, nullptr);
    useOperands(op, state, consumed, nullptr);
    return;
  }
  // A result nothing needs dies where it is made; an element takes its
  // reference where it is read.
  for (Value result : op->getResults()) {
    ValueId id = idOf(result);
    if (roles[id] == Role::Owned && !walk.state.live.test(id.index()))
      death(id, Where::past(op), Death::Reading, walk.state);
    if (roles[id] == Role::Element)
      elementDups.push_back(id);
  }
  State &state = std::get<BlockWalk>(stack.back()).state;
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
  OpWalk regions{op, runsOf(op), state, op->getNumRegions(), {}, llvm::BitVector(count.value()),
                 llvm::BitVector(count.value())};
  regions.entries.resize(op->getNumRegions());
  if (regions.runs == Runs::Repeats)
    regions.held = heldBy(op);
  for (int at = regions.after.live.find_first(); at >= 0; at = regions.after.live.find_next(at))
    if (roles[idAt(at)] == Role::Part && !pinned.test(at)) {
      regions.pinnedHere.set(at);
      pinned.set(at);
    }
  stack.push_back(std::move(regions));
}

void Placement::stepOp() {
  auto &walk = std::get<OpWalk>(stack.back());
  if (walk.remaining > 0) {
    unsigned index = --walk.remaining;
    Region &region = walk.op->getRegion(index);
    if (region.empty())
      return;
    Block &entry = region.front();
    stack.push_back(BlockWalk{&entry, &entry.back(), State{llvm::BitVector(count.value()), Ahead::Allocation}, index});
    return;
  }
  State before = finishOp(walk);
  OpWalk finished = std::move(std::get<OpWalk>(stack.back()));
  pinned.reset(finished.pinnedHere);
  stack.pop_back();
  State &state = std::get<BlockWalk>(stack.back()).state;
  state = std::move(before);
  // The op's own operands, read or moved as it begins: a value its regions
  // need is live into it already.
  llvm::BitVector inside = state.live;
  llvm::SmallBitVector consumed = consumedBy(finished.op);
  operandDeaths(finished.op, consumed, state, &inside, &finished.after);
  useOperands(finished.op, state, consumed, &inside);
}

void Placement::finishBlock() {
  BlockWalk walk = std::move(std::get<BlockWalk>(stack.back()));
  stack.pop_back();
  // The block's arguments are made at its start: one nothing needs dies
  // there.
  for (BlockArgument arg : walk.block->getArguments()) {
    ValueId id = idOf(arg);
    if (roles[id] == Role::Owned && !walk.state.live.test(id.index()))
      death(id, Where::atStart(*walk.block), Death::Reading, walk.state);
    walk.state.live.reset(id.index());
  }
  if (stack.empty())
    return;
  std::get<OpWalk>(stack.back()).entries[walk.region] = std::move(walk.state);
}

// What is live as a region op begins, its regions walked: for an op that
// enters one region once, what any region it enters needs, each region
// dropping at its head (or taking apart, where a part of it lives on) what a
// sibling needs and it does not; for one that may repeat, what it holds
// across its regions and what is live after it. The parts pinned at the op
// take their references before it, where their owners still live.
State Placement::finishOp(OpWalk &walk) {
  Operation *op = walk.op;
  State before{llvm::BitVector(count.value()), walk.after.ahead};
  if (walk.runs == Runs::Repeats) {
    before.live = walk.after.live;
    before.live |= walk.held;
  } else {
    auto branch = cast<RegionBranchOpInterface>(op);
    llvm::SmallVector<RegionSuccessor> entries;
    branch.getSuccessorRegions(RegionBranchPoint::parent(), entries);
    // The counted values some entered region needs, before any head acts.
    llvm::BitVector owners(count.value());
    for (const RegionSuccessor &entry : entries)
      if (const std::optional<State> &state = walk.entries[entry.getSuccessor()->getRegionNumber()])
        owners |= state->live;
    for (int at = owners.find_first(); at >= 0; at = owners.find_next(at))
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
      for (int at = dead.find_first(); at >= 0; at = dead.find_next(at))
        death(idAt(at), Where::atStart(region->front()), Death::Reading, *state);
      before.live |= state->live;
      if (state->ahead == Ahead::Allocation)
        before.ahead = Ahead::Allocation;
    }
    before.live |= owners;
  }
  for (int at = walk.pinnedHere.find_first(); at >= 0; at = walk.pinnedHere.find_next(at)) {
    ValueId part = idAt(at);
    ValueId owner = *ownerOf[part];
    bool ownerLives = before.live.test(owner.index()) ||
                      llvm::any_of(op->getOperands(), [&](Value operand) { return idOf(operand) == owner; });
    if (!ownerLives)
      continue;
    dupSupplies.push_back({Where::before(op), part});
    before.live.reset(at);
  }
  // A value an op that repeats holds across its regions, and nothing needs
  // after it, dies as the op ends.
  if (walk.runs == Runs::Repeats) {
    State after = walk.after;
    after.live.reset(walk.pinnedHere);
    llvm::BitVector dying = walk.held;
    dying.reset(walk.after.live);
    for (int at = dying.find_first(); at >= 0; at = dying.find_next(at))
      if (roles[idAt(at)] == Role::Owned)
        death(idAt(at), Where::past(op), Death::Reading, after);
  }
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
