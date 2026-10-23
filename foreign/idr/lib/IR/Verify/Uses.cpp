// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A value's structural source (sourceOf) and each op's answer to it
// (ValueSourceOpInterface), the values seen through the positions their
// grades put them in, and, by them and upstream's buffer views, which
// constructor has a cell and what a view was read from: shared by the
// verifier and the ownership passes, so each has one meaning.

#include "idr/Analysis/Ownership/Facts.h"
#include "idr/IR/Effects/Classify.h"
#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Ownership.h"
#include "idr/IR/Symbols.h"
#include "idr/Support/Match.h"

#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "mlir/Interfaces/ViewLikeInterface.h"
#include "llvm/ADT/STLExtras.h"

#include <cassert>
#include <cstdint>
#include <optional>

using namespace mlir;
using namespace idr;

//===----------------------------------------------------------------------===//
// Values through their positions
//===----------------------------------------------------------------------===//

namespace {

// The value a cast into or out of a linear position moved: the operand of
// an op that keeps its operand's value (Idr_SameValue) at other uses.
std::optional<Value> linearPositionOf(Value value) {
  Operation *def = value.getDefiningOp();
  if (!def || !def->hasTrait<SameValue>())
    return std::nullopt;
  Value moved = def->getOperand(0);
  if (usesOf(moved.getType()) == usesOf(value.getType()))
    return std::nullopt;
  return moved;
}

} // namespace

SmallVector<Value, 4> idr::linearPositions(Value value) {
  return definitionChain(value, linearPositionOf);
}

Value idr::throughLinear(Value value) { return linearPositions(value).back(); }

// A value is what the op that makes it says: an op that keeps its
// operand's value gives it on as its result (Idr_SameValue), and an op that
// makes a value that is another, or a field of one, answers for each value
// it makes (ValueSourceOpInterface). Anything else is made here: a
// function's parameter, and every value of an op that says neither.
Source idr::sourceOf(Value value) {
  auto result = dyn_cast<OpResult>(value);
  Operation *op =
      result ? result.getOwner() : cast<BlockArgument>(value).getOwner()->getParentOp();
  if (result && op->hasTrait<SameValue>())
    return Same{op->getOperand(0)};
  if (auto sourced = dyn_cast_if_present<ValueSourceOpInterface>(op))
    return sourced.getValueSource(value);
  return Made{};
}

//===----------------------------------------------------------------------===//
// What each op makes its values of
//===----------------------------------------------------------------------===//

namespace {

// A match enters each of its regions with the operands that enter it
// refined, as upstream's region branch interface says (a data match its
// scrutinee first, then what it forwards; a literal match its scrutinee):
// each argument is the operand that enters it, at a type that says more.
// A result is what a region yields, made here.
template <class Match>
Source enteredAs(Match match, Value made) {
  auto arg = dyn_cast<BlockArgument>(made);
  if (!arg)
    return idr::Made{};
  OperandRange entering = match.getEntrySuccessorOperands(RegionSuccessor(arg.getParentRegion()));
  return idr::Same{entering[arg.getArgNumber()]};
}

} // namespace

// A loan's view is the value it lends, and the owner it gives back is that
// value; its lifetime and what its region yields are made here.
Source idr::LendOp::getValueSource(Value made) {
  if (made == getReturned() || made == getView())
    return idr::Same{getOwner()};
  return idr::Made{};
}

// A field read takes its operand refined to one constructor, which its
// operand's constraint holds and its type names (getTag): its one result is
// that constructor's field.
Source idr::DataFieldOp::getValueSource(Value made) {
  assert(made == getResult() && "a field read makes one value");
  return idr::Field{getValue(), getTag(), static_cast<unsigned>(getIndex())};
}

Source idr::DataMatchOp::getValueSource(Value made) { return enteredAs(*this, made); }

Source idr::LitMatchOp::getValueSource(Value made) { return enteredAs(*this, made); }

// What counting and linearity make of an array changes which value names
// it, not which cell it is.
Value idr::arrayRoot(Value array) {
  using Next = std::optional<Value>;
  return definitionChain(array, [](Value value) {
           return match(
               sourceOf(value), [](const Same &same) -> Next { return same.value; },
               [](Made) -> Next { return std::nullopt; },
               [](const Field &) -> Next { return std::nullopt; });
         }).back();
}

// Each value the grade changes make of `value` is the result of a use of
// the one before, so the values form a tree rooted at `value` and each is
// met once; in an unreachable block an op may carry its own result, which
// the walk does not follow back.
bool idr::fieldReadOnce(Value value, unsigned index) {
  unsigned reads = 0;
  SmallVector<Value, 4> work{value};
  while (!work.empty()) {
    Value held = work.pop_back_val();
    for (Operation *user : held.getUsers()) {
      if (user->hasTrait<ResultCarriesOperand>()) {
        if (user->getResult(0) != held)
          work.push_back(user->getResult(0));
        continue;
      }
      auto read = dyn_cast<DataFieldOp>(user);
      if (!read)
        return false;
      if (read.getIndex() == index)
        ++reads;
    }
  }
  return reads == 1;
}

//===----------------------------------------------------------------------===//
// What the ownership passes share
//===----------------------------------------------------------------------===//

bool idr::buildsCell(Type type, Tag tag) {
  DataType data = dataTypeOf(type);
  return data && data.layout() == Layout::Cell && !data.ctor(tag).fields.empty();
}

namespace {

// A view of a buffer lives while the buffer it views does. A counted
// element is read from its buffer, which holds its reference. Each is read
// off the operand itself, not the op's typed accessor: counting grades a
// buffer a step before it gives each read of it the bare view upstream's op
// takes, and the steps between ask what was read from what. Every
// view-like op, upstream's and ours, takes its source first.
std::optional<Value> bufferOf(Value value) {
  if (auto view = value.getDefiningOp<ViewLikeOpInterface>(); view && view.getViewDest() == value)
    return view->getOperand(0);
  if (auto load = value.getDefiningOp<memref::LoadOp>();
      load && holdsReferences(load.getType()))
    return load.getMemrefMutable().get();
  return std::nullopt;
}

// One step up a view's chain: what `value` was read from, or the value it
// is (sourceOf's Same): the operand of an op that keeps its operand's
// value (a linear position), a loan's view, or a match region's refined
// operand. idr.count.share is not such an op: its result holds the
// reference its operand gave up, so a view of it is a view of the result.
std::optional<Value> viewedFrom(Value value) {
  using Next = std::optional<Value>;
  return match(
      sourceOf(value), [](const Field &field) -> Next { return field.scrutinee; },
      [&](const Same &same) -> Next { return bufferOf(value).value_or(same.value); },
      [&](Made) { return bufferOf(value); });
}

} // namespace

// Whether an op of upstream's writes the value `operand` holds into memory:
// the value of a memref.store, not the buffer it writes. The buffer then
// holds the value, and the reference with it. A buffer the op reads (a
// copy's source, a linalg op's input) is memory it reads, not a value it
// stores: an operand any effect of the op names is never stored. Asked of
// the effect system's one classifier: an op that says nothing MLIR can read
// touches both questions, and so stores nothing anyone can place.
bool idr::ownership::storedBy(OpOperand &operand) {
  Operation *user = operand.getOwner();
  if (isa_and_nonnull<IdrDialect>(user->getDialect()))
    return false;
  Value held = operand.get();
  bool writes = effects::classify(user, [](const effects::Effect &each) {
                  return each.kind == effects::Kind::Write;
                }) == effects::Does::Touches;
  bool names = effects::classify(user, [&](const effects::Effect &each) {
                 return each.value == held;
               }) == effects::Does::Touches;
  return writes && !names;
}

// A field is read from its constructor value (sourceOf's Field: an
// idr.data.field of the value refined to one constructor, a memo cell's part
// included); a match's region binds its scrutinee refined, the same value,
// and reads nothing from it. The flow edges are not asked: they also move a
// force's value and an array's element out of what holds them, which would
// make each a view of its cell, and carry nothing for a field that is a
// word.
Value idr::ownership::readFrom(Value value) {
  return match(
      sourceOf(value), [](const Field &field) { return field.scrutinee; },
      [&](const Same &) { return bufferOf(value).value_or(Value()); },
      [&](Made) { return bufferOf(value).value_or(Value()); });
}

// A view's chain goes up through what each step was read from and through
// the values each step is, to the value as it was made: it stops at a
// share, whose result holds a reference of its own.
Value idr::ownership::viewRoot(Value value) { return definitionChain(value, viewedFrom).back(); }

// A result is made by its op, and an argument of a region by the region's
// op, which declares what moves into it. Whether the value moved out of a
// part holds the reference its place held is what that place holds after
// the op (placeAfter), the question exclusivity and the local rule ask too.
std::optional<Value> idr::ownership::ownerOfPart(Value value) {
  Operation *op = isa<OpResult>(value) ? value.getDefiningOp()
                                       : cast<BlockArgument>(value).getOwner()->getParentOp();
  if (!op || !holdsReferences(value.getType()))
    return std::nullopt;
  FlowEdges edges;
  flowEdgesOf(op, edges);
  std::optional<Value> owner;
  enum class Given : std::uint8_t { Borrowed, OwnReference } given = Given::Borrowed;
  for (const FlowEdges::Edge &edge : edges.edges())
    match(
        edge.move,
        [&](const FlowEdges::Flow &flow) {
          bool intoValue = match(
              flow.to.at, [&](const FlowSource::Whole &to) { return to.value == value; },
              [](const OneOf<FlowPlace::Part, FlowSource::Parameter, FlowSource::Result> auto &) {
                return false;
              });
          if (!intoValue)
            return;
          match(
              flow.from.at,
              // A view of the whole where the place keeps the reference it
              // held; that reference itself where the op empties the place.
              [&](const FlowSource::Part &part) {
                switch (placeAfter(edges, part)) {
                case PlaceAfter::Kept:
                  owner = part.value();
                  return;
                case PlaceAfter::Emptied:
                  given = Given::OwnReference;
                  return;
                }
              },
              [](const OneOf<FlowSource::Taken, FlowSource::Whole, FlowSource::Parameter,
                             FlowSource::Result> auto &) {});
        },
        [&](const FlowEdges::Fresh &fresh) {
          if (fresh.to == value)
            given = Given::OwnReference;
        },
        [](const OneOf<FlowEdges::Unify, FlowEdges::Source, FlowEdges::Release,
                       FlowEdges::Overwrite, FlowEdges::Fill, FlowEdges::Constant,
                       FlowEdges::Dispatch> auto &) {});
  if (given == Given::OwnReference)
    return std::nullopt;
  return owner;
}
