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
// it, whose constructor a force may change, or below which a buffer stands
// between it and the part, gives each part a dup while it still lives. A
// part still needed after a region op takes its reference before the op,
// so no region supplies it on only one of its paths. A view a lifetime
// frees is never consumed: borrowing made it a view only where nothing
// takes it over, so a consuming use of one is that promise broken, an
// internal error.
//
// An element read out of memory is a part of its buffer too, where nothing
// may overwrite it while it, or a part read from it, is in use: no op that
// runs then writes memory in place, as their row says, or, for a buffer
// whose type claims it unshared, none writes that buffer. MLIR's effects
// name values, and distinct values may alias, so a write through any other
// value may overwrite a buffer nothing claims unshared. Any other element
// takes its reference where it is read. An element of a view's buffer is
// lent: the view's lifetime keeps the buffer, so it holds no reference,
// nothing drops it, and a use that consumes it takes a dup.
//
// A loan to upstream's ops (idr.carrier) is a reference of no one's: of a
// counted holder it is a part, the holder held across the op whose region
// binds the loan's lifetime and dropped after it; of a view or of static
// data it is lent.
//
// On a path that ends the process (a crash, an exit), every value is freed
// before the path's last allocation, so the end is never reached for want of
// memory; a drop after that allocation is not placed, since nothing follows
// it but the end.
//
// The walk is iterative, its stacks on the heap: a nesting of any depth
// costs no native stack. It decides everything on the function as it came, and
// the rewrite follows it.
#include "idr/Transforms/Counting/Placement.h"

#include "idr/IR/Effects/Classify.h"
#include "idr/IR/Effects/Whole.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Lifetimes.h"
#include "idr/IR/Ownership.h"
#include "idr/Transforms/Counting.h"
#include "idr/Transforms/Pipeline.h"

#include "llvm/ADT/STLExtras.h"

#include <algorithm>
#include <concepts>
#include <optional>

#define GEN_PASS_DEF_IDRRCPLACE
#include "idr/IR/Generated/PassDialects.h.inc"

namespace idr {
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace idr::counting::placement {

//===----------------------------------------------------------------------===//
// What each value is
//===----------------------------------------------------------------------===//

namespace {

// The last op of `block` that holds a use of `element`, or of a value read
// out of it (`readOutOf`: a part, an element of its memory), at any depth:
// while that op runs the element is in use. The read itself where nothing
// uses it.
template <std::predicate<Value, Value> ReadOutOf>
Operation *lastUseIn(Value element, Block &block, ReadOutOf &readOutOf) {
  Operation *last = element.getDefiningOp();
  llvm::SmallVector<Value, 4> reached{element};
  while (!reached.empty()) {
    Value value = reached.pop_back_val();
    for (OpOperand &use : value.getUses()) {
      Operation *at = block.findAncestorOpInBlock(*use.getOwner());
      if (last->isBeforeInBlock(at))
        last = at;
      for (Value made : use.getOwner()->getResults())
        if (readOutOf(made, value))
          reached.push_back(made);
    }
  }
  return last;
}

// What an op, with everything in it, writes in place: the roots of the
// memory each write names (ownership::viewRoot), or anywhere, where a write
// names no value or the op says nothing MLIR can read.
struct Written {
  effects::Does anywhere;
  llvm::SmallVector<Value, 2> roots;
};

Written writtenBy(Operation *op) {
  Written written;
  written.anywhere = effects::classify(op, [&](const effects::Effect &each) {
    if (each.kind != effects::Kind::Write ||
        !effects::atOrAbove[effects::ResourceId::Contents].contains(each.resource))
      return false;
    if (!each.value)
      return true;
    written.roots.push_back(ownership::viewRoot(each.value));
    return false;
  });
  return written;
}

} // namespace

// Each element read out of memory, with what may overwrite it while it is
// in use: one pass over each block that reads one, each op's row read once,
// and what an op writes read once, where a buffer claimed unshared is open
// across it.
void Placement::findElements() {
  solver::inWalkOrder(fn, [&](Value value) {
    if (freedBy(value.getType(), Release::Counted))
      if (std::optional<Value> buffer = elementBufferOf(value))
        elements[idOf(value)] = ElementRead{idOf(*buffer), Overwrites::Nothing};
  });
  auto readOutOf = [&](Value made, Value from) {
    const std::optional<ElementRead> &element = elements[idOf(made)];
    return ownership::readFrom(made) == from || (element && element->buffer == idOf(from));
  };
  // An element in use across the ops met: the last op that uses it, and the
  // root of its buffer's memory where the buffer's type claims it unshared.
  struct Open {
    ValueId element;
    Operation *last;
    std::optional<Value> unshared;
  };
  fn.walk([&](Block *block) {
    llvm::SmallVector<Open, 4> open;
    for (Operation &op : *block) {
      if (!open.empty() && effects::rowOf(&op).contains(effects::Atom::write)) {
        std::optional<Written> written;
        for (Open &each : open) {
          Overwrites &seen = elements[each.element]->overwrites;
          if (!each.unshared) {
            seen = Overwrites::Maybe;
            continue;
          }
          if (!written)
            written = writtenBy(&op);
          if (written->anywhere == effects::Does::Touches ||
              llvm::is_contained(written->roots, *each.unshared))
            seen = Overwrites::Maybe;
          else if (seen == Overwrites::Nothing)
            seen = Overwrites::OtherMemory;
        }
      }
      llvm::erase_if(open, [&](const Open &each) { return each.last == &op; });
      for (Value result : op.getResults()) {
        const std::optional<ElementRead> &element = elements[idOf(result)];
        if (!element)
          continue;
        Operation *last = lastUseIn(result, *block, readOutOf);
        if (last == &op)
          continue;
        Value buffer = valueOf(element->buffer);
        std::optional<Value> unshared;
        if (claims(buffer.getType(), Unique::Self))
          unshared = ownership::viewRoot(buffer);
        open.push_back(Open{idOf(result), last, unshared});
      }
    }
  });
}

// A field read of a counted value, or of a part of one, gives a part; a
// view of a buffer that is counted, or a part of one, gives a part too, and
// so does an element read out of it where nothing may overwrite it while it
// is in use. A part of a lent value is lent. A read its op makes fresh (a
// field re-packed into a fresh cell or array) is no part: its type says who
// frees it, as any value's. The parts of a value are its rows, built in one
// pass in id order.
void Placement::classify() {
  findElements();
  takesWhereRead.resize(count.value());
  std::vector<std::pair<std::uint32_t, ValueId>> pairs;
  // `id`, read from `from`, a part of the owner `from` is or is a part of.
  auto partOf = [&](ValueId id, ValueId from, std::optional<unsigned> field) {
    roles[id] = Role::Part;
    ownerOf[id] = roles[from] == Role::Owned ? from : *ownerOf[from];
    readFromOf[id] = from;
    fieldOf[id] = field;
    pairs.emplace_back(from.index(), id);
  };
  solver::inWalkOrder(fn, [&](Value value) {
    ValueId id = idOf(value);
    Type type = value.getType();
    Operation *def = value.getDefiningOp();
    if (const std::optional<ElementRead> &element = elements[id]) {
      // The buffer kept alive while the element is in use: a counted one
      // this walk places, or a view a lifetime keeps. Only a counted one
      // gives the element its reference where it moves, as a part's owner
      // does, so only there may a write through another value of a buffer
      // claimed unshared leave the element a view.
      Role buffer = roles[element->buffer];
      bool counted = buffer == Role::Owned || buffer == Role::Part;
      bool kept = element->overwrites == Overwrites::Nothing ||
                  (element->overwrites == Overwrites::OtherMemory && counted);
      if (kept && counted)
        partOf(id, element->buffer, std::nullopt);
      else if (kept && (buffer == Role::Scoped || buffer == Role::Lent))
        roles[id] = Role::Lent;
      else {
        roles[id] = Role::Owned;
        takesWhereRead.set(id.index());
      }
      return;
    }
    if (Value source = ownership::readFrom(value);
        source && holdsReferences(type) && readWithoutReference(value)) {
      ValueId from = idOf(source);
      std::optional<unsigned> field;
      if (auto read = dyn_cast_if_present<DataFieldOp>(def))
        field = static_cast<unsigned>(read.getIndex());
      CarrierOp loan = lifetimes::loanOf(value);
      switch (roles[from]) {
      case Role::Owned:
      case Role::Part:
        partOf(id, from, field);
        // A counted holder outlives its loan's lifetime: the op whose region
        // that lifetime is the extent of holds it across its regions.
        if (loan && loan.getResult() == value)
          lent.emplace_back(idOf(lifetimes::extentOf(loan.getLifetime())).index(), *ownerOf[id]);
        return;
      case Role::Lent:
        if (freedBy(type, Release::Counted)) {
          roles[id] = Role::Lent;
          return;
        }
        break;
      case Role::Untouched:
      case Role::Scoped:
        // A loan of a view or of static data: what keeps its holder keeps
        // it, and nothing counts it.
        if (loan) {
          roles[id] = Role::Lent;
          return;
        }
        break;
      }
    }
    // A reference that upstream's memory takes over from counting.
    if (isa_and_present<OwnGiveOp>(def))
      return;
    // Who frees the value, its hold says: a value with no hold holds no
    // reference and static data is never freed, so nothing is placed for
    // either; a view its lifetime frees holds no reference of its own, so no
    // use consumes it; a counted value holds one, which one use on each path
    // consumes.
    std::optional<Hold> hold = holdOf(type);
    if (!hold)
      return;
    switch (hold->release()) {
    case Release::Static:
      return;
    case Release::Scoped:
      roles[id] = Role::Scoped;
      return;
    case Release::Counted:
      roles[id] = Role::Owned;
      return;
    }
  });
  auto byFirst = [](const std::pair<std::uint32_t, ValueId> &a,
                    const std::pair<std::uint32_t, ValueId> &b) { return a.first < b.first; };
  llvm::stable_sort(pairs, byFirst);
  llvm::stable_sort(lent, byFirst);
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
// The pass
//===----------------------------------------------------------------------===//

void Placement::run() {
  classify();
  pinned.resize(count.value());
  Block &body = fn.getBody().front();
  blocks.push_back(BlockWalk{&body, &body.back(), State{llvm::BitVector(count.value()), Ahead::Allocation}, 0});
  while (!blocks.empty() && succeeded(outcome)) {
    if (blocks.size() > ops.size())
      stepBlock(blocks.back());
    else
      stepOp(ops.back());
  }
  if (succeeded(outcome))
    apply();
}

namespace {

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

} // namespace idr::counting::placement
