// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What idr-rc-place's walk (Placement.h) places at each use and each death
// of a value: a consuming use of a counted value still needed later takes
// a dup, a part used while its owner lives reads it, and a value no later
// use needs dies, given up where only a read used it last: dropped, or
// taken apart where it is used once. A dying owner's
// parts still needed take their references there, the owner taken apart
// (drop specialization) or each part given a dup while the owner lives.
#include "idr/Transforms/Counting/Placement.h"

#include "idr/IR/Effects/Whole.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Tail.h"

#include "llvm/ADT/STLExtras.h"

#include <algorithm>

using namespace mlir;

namespace idr::counting::placement {

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
    if (lastActOf(op)) {
      fail(op, "a call in tail position reads a counted value no later use needs, so its drop "
               "would follow the call");
      continue;
    }
    State dying = after ? *after : state;
    death(id, Where::past(op), Death::Reading, dying);
  }
}

// Each operand of `op`, against what is live after it: a consuming use of a
// counted value still needed later takes a dup; a use of a part while what
// it was read from still holds it reads it, and a consuming one takes a dup
// of it; a part used where nothing it was read from lives any more holds a
// reference of its own, and is placed as a counted value from then on,
// dying at its last use as one does; a lent value's owner lives past the
// call, so a consuming use of it takes a dup and nothing else is placed.
// Last, a point before an op that may acquire memory has an allocation
// ahead.
void Placement::useOperands(Operation *op, State &state, const llvm::SmallBitVector &consumed,
                            const llvm::BitVector *inside) {
  // A call nothing may follow, past which no drop can be placed.
  FunctionCallOpInterface last = lastActOf(op);
  // Whether a value `part` was read from holds it at `op`, up the chain of
  // what each was read from to its owner: one that lives there, the owner
  // or a part that took a reference of its own, keeps the memory the part
  // reads, so the part is a view of it there.
  auto held = [&](ValueId part) {
    for (std::optional<ValueId> from = readFromOf[part]; from;
         from = roles[*from] == Role::Part ? readFromOf[*from] : std::nullopt)
      if (aliveAt(*from, op, state))
        return true;
    return false;
  };
  llvm::SmallVector<ValueId, 4> used;
  for (OpOperand &operand : op->getOpOperands()) {
    ValueId id = idOf(operand.get());
    unsigned index = operand.getOperandNumber();
    bool consumes = consumed.test(index);
    bool needed = state.live.test(id.index()) || llvm::is_contained(used, id) ||
                  (inside && inside->test(id.index()) && consumes);
    switch (roles[id]) {
    // A view holds no reference of its own, so the rule moves none on.
    case Role::Untouched:
    case Role::Scoped:
      break;
    case Role::Lent:
      if (consumes)
        dups.push_back({op, index});
      break;
    case Role::Owned:
      if (consumes && needed)
        dups.push_back({op, index});
      used.push_back(id);
      break;
    case Role::Part: {
      if (state.live.test(id.index()) || llvm::is_contained(used, id)) {
        // Owned from here on: placed as a counted value.
        if (consumes && needed)
          dups.push_back({op, index});
        used.push_back(id);
        break;
      }
      if (held(id)) {
        // A view of what holds it: a use that consumes it takes a dup.
        if (consumes)
          dups.push_back({op, index});
        break;
      }
      // Nothing it was read from lives here: it holds a reference of its own
      // from here on, and this is its last use, so it dies here as a counted
      // value does, moved on by a use that consumes it or given up right
      // after one that reads it, and the parts read from it that are still
      // needed take their references from it first. Given up alone, a part
      // read from it would read memory its giving up may free.
      bool moves = llvm::any_of(op->getOpOperands(), [&](OpOperand &other) {
        return other.get() == operand.get() && consumed.test(other.getOperandNumber());
      });
      if (moves)
        death(id, Where::before(op), Death::Consuming, state);
      else if (last && state.ahead == Ahead::Allocation)
        fail(op, "a call in tail position reads a part no later use needs");
      else
        death(id, Where::past(op), Death::Reading, state);
      used.push_back(id);
      break;
    }
    }
  }
  for (ValueId id : used)
    state.live.set(id.index());
  if (effects::mayAcquire(op))
    state.ahead = Ahead::Allocation;
}

namespace {

// Whether the values from a dying owner down to a part of it can each be
// taken apart in turn to give the part its reference: every one of them a
// value whose type fixes its constructor and that is no memo cell. A
// buffer on the way, or a memo cell, blocks it, and the part takes a dup.
enum class Way : std::uint8_t { Open, Blocked };

Way through(Way above, Type type) {
  return above == Way::Open && knownConstructor(type) && !isMemo(type) ? Way::Open
                                                                      : Way::Blocked;
}

} // namespace

// `value` is given up at `where`, its last use behind it: dropped, or, used
// once, taken apart (GiveUpAt), which reads the constructor its type fixes.
// Idris lets a value used once die after reads only where its fields were
// read, which only a value refined to one constructor can be, or where a
// case bound it refined and left it unread. A value used once whose type
// fixes no constructor has no take to end its owner and no drop may: an
// internal error, never a drop.
void Placement::giveUp(Where where, ValueId value) {
  Value given = valueOf(value);
  Type type = given.getType();
  if (usesOf(type) == Uses::Once && !isTakeable(type) && !isUnpackable(type))
    return fail(given, "a value used once dies where no take can end its owner: its type fixes "
                       "no one constructor a take or an unpack moves the fields of");
  givesUp.push_back({where, value});
}

// `owner` dies at `where`: the parts of it still needed take their
// references (taken apart from it, or each a dup while it lives), and it is
// given up, unless only the end lies ahead or its death moved it on.
void Placement::death(ValueId owner, Where where, Death kind, State &state) {
  Type type = valueOf(owner).getType();
  Way way = kind == Death::Reading ? through(Way::Open, type) : Way::Blocked;
  llvm::SmallVector<ValueId, 4> needed;
  llvm::SmallVector<std::pair<ValueId, Way>, 8> pending{{owner, way}};
  while (!pending.empty()) {
    auto [at, above] = pending.pop_back_val();
    for (const auto &[index, part] : childrenOf(at)) {
      if (pinned.test(part.index()))
        continue;
      if (state.live.test(part.index())) {
        needed.push_back(part);
        if (above == Way::Blocked)
          way = Way::Blocked;
      } else {
        pending.emplace_back(part, through(above, valueOf(part).getType()));
      }
    }
  }
  if (needed.empty()) {
    if (kind == Death::Reading && state.ahead == Ahead::Allocation)
      giveUp(where, owner);
    return;
  }
  for (ValueId part : needed)
    state.live.reset(part.index());
  if (way == Way::Blocked) {
    // Each part takes a dup while its owner still lives; the owner is then
    // given up after them.
    for (ValueId part : needed)
      dupSupplies.push_back({where, part});
    largestDupSupply = std::max(largestDupSupply, static_cast<unsigned>(needed.size()));
    if (kind == Death::Reading && state.ahead == Ahead::Allocation)
      giveUp(where, owner);
    return;
  }
  takeSupplies.push_back({where, owner, std::move(needed), state.ahead});
}

} // namespace idr::counting::placement
