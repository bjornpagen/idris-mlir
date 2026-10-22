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
#include "idr/Transforms/Counting/Placement.h"

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Ownership.h"
#include "idr/Transforms/Counting.h"
#include "idr/Transforms/Pipeline.h"

#include "llvm/ADT/STLExtras.h"

#include <algorithm>

namespace idr {
#define GEN_PASS_DEF_IDRRCPLACE
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace idr::counting::placement {

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
// The pass
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
