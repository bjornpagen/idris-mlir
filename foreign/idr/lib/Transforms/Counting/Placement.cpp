// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-rc-place: the dups and drops that make every counted reference
// consumed exactly once on every path, placed by one reverse walk of each
// function over its regions, the set of values some later use needs as the
// walk's one state. A value's grade says what there is to place:
//   - a value freed by its count holds one reference of its own: a
//     consuming use while a later use still needs it takes a dup, and it is
//     dropped right after its last use, or at the head of a region that
//     does not need it when a sibling region does; one Idris lets be used
//     once has one use, so it is moved or dropped, never duplicated;
//   - a view (scoped) holds none and nothing drops it; static data needs
//     nothing.
// A region op that enters one of its regions once per run moves what its
// regions need into them; one that may run a region any number of times, or
// none, holds what its regions read across it, and inside it each consuming
// use takes a dup. Nothing is placed after a call in tail position or modulo
// a context: a drop it would need is a caller's promise broken, an internal
// error.
//
// A part of a counted value (a field read of it, a view of its buffer)
// holds no reference while the value does: it is read while its owner
// lives, and a use that consumes it takes a dup of it, the dup taken from
// the counted value it was read from. Where the owner dies while a part of
// it is still needed, the part takes a reference there: the owner, whose
// constructor its type fixes, is taken apart at that point and the parts
// move out of it (drop specialization); an owner whose last use consumes
// it, or whose constructor a force may change, gives each part a dup while
// it still lives. A part still needed after a region op takes its
// reference before the op, so no region supplies it on only one of its
// paths. A view a lifetime frees is never consumed: borrowing made it a
// view only where nothing takes it over, so a consuming use of one is that
// promise broken, an internal error.
//
// On a path that ends the process (a crash, an exit), every value is freed
// before the path's last allocation, so the end is never reached for want of
// memory; a drop after that allocation is not placed, since nothing follows
// it but the end.
//
// The walk is iterative, its stack on the heap: a nesting of any depth costs
// no native stack. It decides everything on the function as it came, and
// the rewrite follows it.
#include "Counting.h"

#include "idr/Analysis/Solver/Extraction.h"
#include "idr/IR/Effects/Query.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Ownership.h"
#include "idr/Support/Id.h"
#include "idr/Transforms/Counting.h"
#include "idr/Transforms/Pipeline.h"

#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/BitVector.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallBitVector.h"

#include <algorithm>
#include <optional>
#include <variant>

namespace idr {
#define GEN_PASS_DEF_IDRRCPLACE
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace idr::counting {
namespace {

struct ValueTag {
  using Minter = solver::Numbering<ValueTag>;
};

using ValueId = Id<ValueTag>;

// Whether `op`, with everything in it, may take memory: a cell or a value
// it makes, memory its runtime function holds that no value names, or what
// a call's callee acquires, all of which its row reports as `alloc`.
bool mayAcquire(Operation *op) { return effects::rowOf(op).contains(effects::Atom::alloc); }

// What placement does with a value, decided once from its type and how it
// was made:
//   - Owned: it holds one counted reference of its own;
//   - Part: a part of a counted value (a field read, a view of a buffer),
//     which holds no reference while its owner lives;
//   - Element: read out of mutable memory, so it takes a reference of its
//     own where it is read, the memory being writable while it lives;
//   - Scoped: a view its lifetime frees;
//   - Untouched: nothing to place (no reference, used once, static, or a
//     reference handed over to upstream's memory).
enum class Role : std::uint8_t { Untouched, Owned, Part, Element, Scoped };

// How a value dies at a point: after a use that only reads it (or where it
// is made, unused), or moved on by a use that consumes it.
enum class Death : std::uint8_t { Reading, Consuming };

// What lies ahead of a point on its path before the path leaves the
// function: an allocation or the caller, so a dead value must be freed; or
// only the end of the process, so nothing needs freeing.
enum class Ahead : std::uint8_t { Allocation, End };

struct State {
  llvm::BitVector live;
  Ahead ahead = Ahead::Allocation;
};

// A consuming use that takes a dup of the counted value it names, made
// right before its op.
struct DupAt {
  Operation *user;
  unsigned operand;
};

// A drop of a value at a point: of what supplied it there, when it is a part
// that took a reference of its own.
struct DropAt {
  Where where;
  ValueId value;
};

// A part that takes a reference of its own at a point, by a dup while its
// owner still lives.
struct DupSupply {
  Where where;
  ValueId part;
};

// An owner taken apart at a point, the parts it gives taking their
// references from it; its token freed and its dead fields dropped, unless
// only the end lies ahead.
struct TakeSupply {
  Where where;
  ValueId owner;
  llvm::SmallVector<ValueId, 4> parts;
  Ahead ahead;
};

// The frames of the iterative walk: a block walked backward, and a region op
// whose regions are walked last first, so a join point's targets are walked
// before the body that jumps to them.
struct BlockWalk {
  Block *block;
  Operation *next;
  State state;
  unsigned region;
};
struct OpWalk {
  Operation *op;
  Runs runs;
  State after;
  unsigned remaining;
  llvm::SmallVector<std::optional<State>, 2> entries;
  // What an op that may run its regions many times holds across them.
  llvm::BitVector held;
  // The parts live after the op that its regions may not supply.
  llvm::BitVector pinnedHere;
};
using Frame = std::variant<BlockWalk, OpWalk>;

class Placement {
public:
  explicit Placement(FuncOp fn)
      : fn(fn), numbering(fn), done(finishCopy(numbering)), count(done.count),
        roles(count, Role::Untouched), ownerOf(count, std::optional<ValueId>()),
        readFromOf(count, std::optional<ValueId>()), fieldOf(count, std::optional<unsigned>()) {}

  void run();

  unsigned dupsPlaced = 0;
  unsigned dropsPlaced = 0;
  unsigned takesPlaced = 0;
  // The most parts given a dup at one point: what a frame holds of a dead
  // owner's parts, for the frame bound's record.
  unsigned largestDupSupply = 0;
  // A promise the walk could not keep: an internal error at the op.
  LogicalResult outcome = success();

private:
  static solver::Numbering<ValueTag>::Done finishCopy(const solver::Numbering<ValueTag> &from) {
    solver::Numbering<ValueTag> copy = from;
    return std::move(copy).finish();
  }

  ValueId idOf(Value value) const { return numbering.at(value); }
  ValueId idAt(int bit) const { return count.ids()[static_cast<std::uint32_t>(bit)]; }
  Value valueOf(ValueId id) const { return done.values[id]; }

  void classify();
  void stepBlock();
  void stepOp();
  void finishBlock();
  State finishOp(OpWalk &walk);
  void enterTerminator(Operation *terminator, State &state);
  void operandDeaths(Operation *op, const llvm::SmallBitVector &consumed, State &state,
                     const llvm::BitVector *inside, const State *after);
  void useOperands(Operation *op, State &state, const llvm::SmallBitVector &consumed,
                   const llvm::BitVector *inside);
  void death(ValueId owner, Where where, Death kind, State &state);
  llvm::SmallBitVector consumedBy(Operation *op);
  State successorState(const RegionSuccessor &successor, Operation *terminator);
  OpWalk *frameOf(Operation *op);
  bool aliveAt(ValueId owner, Operation *op, const State &state) const;
  llvm::BitVector heldBy(Operation *op) const;
  llvm::ArrayRef<std::pair<std::uint32_t, ValueId>> childrenOf(ValueId id) const {
    return llvm::ArrayRef(childRows).slice(childStart[id.index()],
                                           childStart[id.index() + 1] - childStart[id.index()]);
  }
  void fail(Operation *at, const llvm::Twine &message) {
    at->emitError("internal error: ") << message;
    outcome = failure();
  }

  void apply();
  Value supplied(ValueId part, Operation *at) const;
  void insertAt(RewriterBase &rewriter, const Where &where);

  FuncOp fn;
  solver::Numbering<ValueTag> numbering;
  solver::Numbering<ValueTag>::Done done;
  Count<ValueId> count;
  IndexVector<ValueId, Role> roles;
  // A part's owner (the counted value it is a part of), the value it was
  // read from, and its field, when a field read made it.
  IndexVector<ValueId, std::optional<ValueId>> ownerOf;
  IndexVector<ValueId, std::optional<ValueId>> readFromOf;
  IndexVector<ValueId, std::optional<unsigned>> fieldOf;
  // The parts read straight from each value, a row per value, each with its
  // field (none for a view of a buffer).
  std::vector<std::pair<std::uint32_t, ValueId>> childRows;
  std::vector<std::uint32_t> childStart;

  llvm::BitVector pinned;
  llvm::SmallVector<Frame, 16> stack;

  llvm::SmallVector<DupAt> dups;
  llvm::SmallVector<DropAt> drops;
  llvm::SmallVector<DupSupply> dupSupplies;
  llvm::SmallVector<TakeSupply> takeSupplies;
  llvm::SmallVector<ValueId> elementDups;
  // What each supplied part became, for the drops of it placed later.
  llvm::SmallVector<std::pair<ValueId, Value>> partValues;
  // The last op the rewrite put at each point, so a drop there follows the
  // takes and dups that read the value it frees.
  llvm::SmallVector<std::pair<Where, Operation *>> lastAt;
};

//===----------------------------------------------------------------------===//
// What each value is
//===----------------------------------------------------------------------===//

// A field read of a counted value, or of a part of one, gives a part; a
// view of a buffer that is counted, or a part of one, gives a part too. An
// element read out of a buffer is read from it as well, but the memory may
// be written while the element lives, so it is an element, decided first.
// The parts of a value are its rows, built in one pass in id order.
void Placement::classify() {
  std::vector<std::pair<std::uint32_t, ValueId>> pairs;
  solver::inWalkOrder(fn, [&](Value value) {
    ValueId id = idOf(value);
    Type type = value.getType();
    Operation *def = value.getDefiningOp();
    if (countsOf(type) == Counts::Counted && readOutOfMemory(value)) {
      roles[id] = Role::Element;
      return;
    }
    std::optional<ValueId> from;
    std::optional<unsigned> field;
    if (Value source = ownership::readFrom(value)) {
      from = idOf(source);
      if (auto read = dyn_cast_if_present<DataFieldOp>(def))
        field = static_cast<unsigned>(read.getIndex());
    }
    if (from && holdsReferences(type)) {
      Role source = roles[*from];
      if (source == Role::Owned || source == Role::Part) {
        roles[id] = Role::Part;
        ownerOf[id] = source == Role::Owned ? *from : *ownerOf[*from];
        readFromOf[id] = *from;
        fieldOf[id] = field;
        pairs.emplace_back(from->index(), id);
        return;
      }
    }
    // A reference that upstream's memory takes over from counting.
    if (isa_and_present<OwnGiveOp>(def))
      return;
    switch (countsOf(type)) {
    case Counts::None:
    case Counts::Static:
      return;
    case Counts::Scoped:
      roles[id] = Role::Scoped;
      return;
    case Counts::Counted:
      break;
    }
    roles[id] = Role::Owned;
  });
  llvm::stable_sort(pairs, [](const auto &a, const auto &b) { return a.first < b.first; });
  childStart.assign(count.value() + 1, 0);
  for (const auto &[from, part] : pairs)
    ++childStart[from + 1];
  for (std::uint32_t at = 0; at < count.value(); ++at)
    childStart[at + 1] += childStart[at];
  childRows.clear();
  for (const auto &[from, part] : pairs)
    childRows.emplace_back(fieldOf[part] ? *fieldOf[part] : ~0u, part);
}

//===----------------------------------------------------------------------===//
// The walk
//===----------------------------------------------------------------------===//

void Placement::run() {
  classify();
  pinned.resize(count.value());
  Block &body = fn.getBody().front();
  stack.push_back(BlockWalk{&body, &body.back(), State{llvm::BitVector(count.value()), Ahead::Allocation}, 0});
  while (!stack.empty() && succeeded(outcome)) {
    if (std::holds_alternative<BlockWalk>(stack.back()))
      stepBlock();
    else
      stepOp();
  }
  if (succeeded(outcome))
    apply();
}

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

// The counted operands of `op` no later use needs: one it only reads dies
// right after it (after the op as a whole, for a region op whose regions do
// not need it); one it consumes, with parts of it still needed, gives them
// dups before it. `inside`, for a region op, is what its regions need, and
// `after` what is live after the op.
void Placement::operandDeaths(Operation *op, const llvm::SmallBitVector &consumed, State &state,
                              const llvm::BitVector *inside, const State *after) {
  llvm::SmallVector<ValueId, 4> seen;
  for (OpOperand &operand : op->getOpOperands()) {
    ValueId id = idOf(operand.get());
    if (roles[id] != Role::Owned || llvm::is_contained(seen, id))
      continue;
    seen.push_back(id);
    const llvm::BitVector &later = after ? after->live : state.live;
    if (later.test(id.index()) || (inside && inside->test(id.index())))
      continue;
    bool consumes = llvm::any_of(op->getOpOperands(), [&](OpOperand &other) {
      return other.get() == operand.get() && consumed.test(other.getOperandNumber());
    });
    if (consumes) {
      death(id, Where::before(op), Death::Consuming, state);
      continue;
    }
    if (op->hasTrait<OpTrait::IsTerminator>()) {
      fail(op, "a terminator reads a counted value nothing after it needs");
      continue;
    }
    if (auto call = dyn_cast<CallOp>(op); call && call.getTailKind() != TailKind::nontail) {
      fail(op, "a call in tail position reads a counted value no later use needs, so its drop "
               "would follow the call");
      continue;
    }
    State dying = after ? *after : state;
    death(id, Where::past(op), Death::Reading, dying);
  }
}

// Each operand of `op`, against what is live after it: a consuming use of a
// counted value still needed later takes a dup; a use of a part while its
// owner lives reads it, and a consuming one takes a dup of it; a part used
// after its owner died has taken a reference of its own, and is placed as a
// counted value from then on. Last, a point before an op that may acquire
// memory has an allocation ahead.
void Placement::useOperands(Operation *op, State &state, const llvm::SmallBitVector &consumed,
                            const llvm::BitVector *inside) {
  bool tail = false;
  if (auto call = dyn_cast<CallOp>(op))
    tail = call.getTailKind() != TailKind::nontail;
  llvm::SmallVector<ValueId, 4> used;
  for (OpOperand &operand : op->getOpOperands()) {
    ValueId id = idOf(operand.get());
    unsigned index = operand.getOperandNumber();
    bool consumes = consumed.test(index);
    bool needed = state.live.test(id.index()) || llvm::is_contained(used, id) ||
                  (inside && inside->test(id.index()) && consumes);
    switch (roles[id]) {
    case Role::Untouched:
    case Role::Element:
      break;
    case Role::Scoped:
      if (consumes)
        fail(op, "a view its lifetime frees is taken over, though borrowing made it a view only "
                 "where nothing takes it over");
      break;
    case Role::Owned:
      if (consumes && needed)
        dups.push_back({op, index});
      used.push_back(id);
      break;
    case Role::Part: {
      ValueId owner = *ownerOf[id];
      if (state.live.test(id.index()) || llvm::is_contained(used, id)) {
        // Owned from here on: placed as a counted value.
        if (consumes && needed)
          dups.push_back({op, index});
        used.push_back(id);
        break;
      }
      if (aliveAt(owner, op, state)) {
        // A part of a living owner: a use that consumes it takes a dup.
        if (consumes)
          dups.push_back({op, index});
        break;
      }
      // Its owner is dead here: it holds a reference of its own from here
      // on, which this use consumes or which is dropped right after it.
      if (!consumes && state.ahead == Ahead::Allocation) {
        if (tail)
          fail(op, "a call in tail position reads a part no later use needs");
        drops.push_back({Where::past(op), id});
      }
      used.push_back(id);
      break;
    }
    }
  }
  for (ValueId id : used)
    state.live.set(id.index());
  if (mayAcquire(op))
    state.ahead = Ahead::Allocation;
}

// `owner` dies at `where`: the parts of it still needed take their
// references (taken apart from it, or each a dup while it lives), and it is
// dropped, unless only the end lies ahead or its death moved it on.
void Placement::death(ValueId owner, Where where, Death kind, State &state) {
  llvm::SmallVector<ValueId, 4> needed;
  llvm::SmallVector<ValueId, 8> pending{owner};
  while (!pending.empty()) {
    ValueId at = pending.pop_back_val();
    for (const auto &[index, part] : childrenOf(at)) {
      if (pinned.test(part.index()))
        continue;
      if (state.live.test(part.index()))
        needed.push_back(part);
      else
        pending.push_back(part);
    }
  }
  Type type = valueOf(owner).getType();
  if (needed.empty()) {
    if (kind == Death::Reading && state.ahead == Ahead::Allocation)
      drops.push_back({where, owner});
    return;
  }
  for (ValueId part : needed)
    state.live.reset(part.index());
  bool takeable = kind == Death::Reading && knownConstructor(type) && !isMemo(type);
  if (!takeable) {
    // Each part takes a dup while its owner still lives; the owner is then
    // dropped after them.
    for (ValueId part : needed)
      dupSupplies.push_back({where, part});
    largestDupSupply = std::max(largestDupSupply, static_cast<unsigned>(needed.size()));
    if (kind == Death::Reading && state.ahead == Ahead::Allocation)
      drops.push_back({where, owner});
    return;
  }
  takeSupplies.push_back({where, owner, std::move(needed), state.ahead});
}

//===----------------------------------------------------------------------===//
// The rewrite
//===----------------------------------------------------------------------===//

// Whether a use by `op` comes after `made`, an op at a point of its block:
// `op` is a later op of that block, or nested in one.
bool after(Operation *made, Operation *op) {
  Operation *ancestor = made->getBlock()->findAncestorOpInBlock(*op);
  return ancestor && ancestor != made && made->isBeforeInBlock(ancestor);
}

// What a part is at `at`: what gave it its reference at a point before
// `at`, or the part itself, a view.
Value Placement::supplied(ValueId part, Operation *at) const {
  for (const auto &[id, value] : partValues)
    if (id == part && (value.getDefiningOp() == at || after(value.getDefiningOp(), at)))
      return value;
  return valueOf(part);
}

// The rewriter at `where`, after what the rewrite already put there, so ops
// put at one point keep the order they were put in.
void Placement::insertAt(RewriterBase &rewriter, const Where &where) {
  for (const auto &[point, last] : llvm::reverse(lastAt))
    if (point == where) {
      rewriter.setInsertionPointAfter(last);
      return;
    }
  rewriter.setInsertionPoint(where.block, where.insertion());
}

void Placement::apply() {
  IRRewriter rewriter(fn->getContext());
  auto record = [&](const Where &where, Operation *made) { lastAt.emplace_back(where, made); };
  // Takes first: the parts they give replace the views at every later use.
  for (TakeSupply &take : takeSupplies) {
    Value owner = valueOf(take.owner);
    insertAt(rewriter, take.where);
    Location loc = owner.getLoc();
    // The owner, then each part beneath a needed one that is dead here,
    // taken apart in turn at the same point.
    llvm::SmallVector<std::pair<Value, ValueId>, 4> wholes{{owner, take.owner}};
    while (!wholes.empty()) {
      auto [whole, wholeId] = wholes.pop_back_val();
      Tag tag = *knownConstructor(whole.getType());
      Operation *made;
      ValueRange fields;
      Value token;
      if (buildsCell(whole.getType(), tag)) {
        auto taken = CountTakeOp::create(rewriter, loc, whole);
        made = taken;
        fields = taken.getFields();
        token = taken.getToken();
      } else {
        auto unpacked = CountUnpackOp::create(rewriter, loc, whole);
        made = unpacked;
        fields = unpacked.getFields();
      }
      ++takesPlaced;
      llvm::SmallBitVector given(fields.size());
      for (const auto &[index, part] : childrenOf(wholeId)) {
        if (index == ~0u || index >= fields.size())
          continue;
        bool needed = llvm::is_contained(take.parts, part);
        bool beneath = llvm::any_of(take.parts, [&](ValueId p) {
          for (std::optional<ValueId> up = readFromOf[p]; up; up = readFromOf[*up])
            if (*up == part)
              return true;
          return false;
        });
        if (!needed && !beneath)
          continue;
        if (given.test(index)) {
          // A second read of one field takes a dup of the first.
          dupSupplies.push_back({take.where, part});
          continue;
        }
        given.set(index);
        Value field = fields[index];
        if (needed) {
          Value view = valueOf(part);
          rewriter.replaceUsesWithIf(view, field,
                                     [&](OpOperand &use) { return after(made, use.getOwner()); });
          partValues.emplace_back(part, field);
        } else {
          wholes.emplace_back(field, part);
        }
      }
      Operation *last = made;
      // The fields nothing needs are dropped, and the emptied cell freed,
      // unless only the end lies ahead.
      if (take.ahead == Ahead::Allocation) {
        rewriter.setInsertionPointAfter(made);
        for (auto [index, field] : llvm::enumerate(fields))
          if (!given.test(index) && countsOf(field.getType()) == Counts::Counted) {
            last = CountDropOp::create(rewriter, loc, field);
            ++dropsPlaced;
          }
        if (token)
          last = TokenFreeOp::create(rewriter, loc, token);
      }
      record(take.where, last);
      rewriter.setInsertionPointAfter(last);
    }
  }
  // Dups that supply a part while its owner lives. The list grows as the
  // takes find a field read twice, so it is walked by index.
  for (std::size_t at = 0; at < dupSupplies.size(); ++at) {
    DupSupply supply = dupSupplies[at];
    Value view = valueOf(supply.part);
    insertAt(rewriter, supply.where);
    auto dup = CountDupOp::create(rewriter, view.getLoc(), atHold(view.getType(), Hold::counted()), view);
    rewriter.replaceUsesWithIf(view, dup.getResult(), [&](OpOperand &use) {
      return use.getOwner() != dup && after(dup, use.getOwner());
    });
    partValues.emplace_back(supply.part, dup.getResult());
    record(supply.where, dup);
    ++dupsPlaced;
  }
  // An element takes its reference where it is read.
  for (ValueId id : elementDups) {
    Value element = valueOf(id);
    rewriter.setInsertionPointAfterValue(element);
    auto dup = CountDupOp::create(rewriter, element.getLoc(), atHold(element.getType(), Hold::counted()), element);
    rewriter.replaceAllUsesExcept(element, dup.getResult(), dup);
    ++dupsPlaced;
  }
  // Dups for the consuming uses of a value still needed later, or of a part
  // while its owner lives.
  for (DupAt &at : dups) {
    OpOperand &operand = at.user->getOpOperand(at.operand);
    Value value = operand.get();
    rewriter.setInsertionPoint(at.user);
    auto dup = CountDupOp::create(rewriter, at.user->getLoc(), atHold(value.getType(), Hold::counted()), value);
    rewriter.modifyOpInPlace(at.user, [&] { operand.set(dup.getResult()); });
    ++dupsPlaced;
  }
  // Drops, after what the rewrite put at their points: of the value a part
  // became where it took its reference.
  for (DropAt &drop : drops) {
    insertAt(rewriter, drop.where);
    Operation *anchor = &*rewriter.getInsertionPoint();
    Value value = roles[drop.value] == Role::Part ? supplied(drop.value, anchor) : valueOf(drop.value);
    record(drop.where, CountDropOp::create(rewriter, value.getLoc(), value));
    ++dropsPlaced;
  }
  // A part read every use of which took its reference elsewhere goes, the
  // reads beneath it first.
  for (std::uint32_t at = count.value(); at-- > 0;) {
    ValueId id = idAt(static_cast<int>(at));
    if (roles[id] != Role::Part)
      continue;
    Value value = valueOf(id);
    if (Operation *def = value.getDefiningOp();
        def && def->use_empty() && effects::whole(def).onlyComputes())
      rewriter.eraseOp(def);
  }
}

struct Place : impl::IdrRcPlaceBase<Place> {
  void runOnProgram(ProgramOp) {
    Placement placement(getOperation());
    placement.run();
    if (failed(placement.outcome))
      return signalPassFailure();
    numDups += placement.dupsPlaced;
    numDrops += placement.dropsPlaced;
    numTakes += placement.takesPlaced;
    largestPartDups.updateMax(placement.largestDupSupply);
  }
};

} // namespace
} // namespace idr::counting
