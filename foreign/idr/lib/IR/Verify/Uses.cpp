// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A value's structural source (sourceOf), the values seen through the
// positions their grades put them in, and, by them and upstream's buffer
// views, which constructor has a cell, what a use does with a reference in
// the owned stage, and what a view was read from: shared by the verifier
// and the ownership passes, so each has one meaning.

#include "idr/IR/Effects/Classify.h"
#include "idr/IR/Effects/Consumption.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Ownership.h"
#include "idr/IR/Symbols.h"

#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Interfaces/ViewLikeInterface.h"
#include "llvm/ADT/STLExtras.h"

#include <cstddef>
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

// A chain closes on itself only in an unreachable block, which MLIR admits,
// so the case is essential. It is found with no set of the values passed:
// each value is the step of the one before, so once a value comes back the
// chain repeats with a fixed period. The value held at each power of two
// steps comes back exactly one period later (Brent's method), and the chain
// ends one period after the first value that comes back, each value in it
// once.
SmallVector<Value, 4> idr::definitionChain(Value start,
                                           function_ref<std::optional<Value>(Value)> step) {
  SmallVector<Value, 4> chain{start};
  std::size_t held = 0;
  std::size_t power = 1;
  for (std::optional<Value> next = step(start); next; next = step(*next)) {
    chain.push_back(*next);
    std::size_t period = chain.size() - 1 - held;
    if (*next == chain[held]) {
      std::size_t first = 0;
      while (chain[first] != chain[first + period])
        ++first;
      chain.truncate(first + period);
      return chain;
    }
    if (period == power) {
      held = chain.size() - 1;
      power *= 2;
    }
  }
  return chain;
}

SmallVector<Value, 4> idr::linearPositions(Value value) {
  return definitionChain(value, linearPositionOf);
}

Value idr::throughLinear(Value value) { return linearPositions(value).back(); }

// An op says it keeps its operand's value (Idr_SameValue); a field read
// takes its operand refined to one constructor, which its type names; a
// match enters each of its regions with the operands that enter it refined
// (a data match its scrutinee first, then what it forwards; a literal match
// its scrutinee, in its default alone), each argument the same value as the
// operand that enters it, at a type that says more; a loan's view is the
// value it lends, and the owner it gives back is that value.
Source idr::sourceOf(Value value) {
  if (auto result = dyn_cast<OpResult>(value)) {
    Operation *op = result.getOwner();
    if (op->hasTrait<SameValue>())
      return Same{op->getOperand(0)};
    if (auto loan = dyn_cast<LendOp>(op); loan && result == loan.getReturned())
      return Same{loan.getOwner()};
    if (auto read = dyn_cast<DataFieldOp>(op))
      if (std::optional<Tag> tag = dataTypeOf(read.getValue().getType()).singleTag())
        return Field{read.getValue(), *tag, static_cast<unsigned>(read.getIndex())};
    return Made{};
  }
  auto arg = cast<BlockArgument>(value);
  Operation *parent = arg.getOwner()->getParentOp();
  if (auto loan = dyn_cast<LendOp>(parent); loan && arg == loan.getView())
    return Same{loan.getOwner()};
  if (isa<MatchOpInterface>(parent) && arg.getOwner()->isEntryBlock()) {
    OperandRange entering = cast<RegionBranchOpInterface>(parent).getEntrySuccessorOperands(
        RegionSuccessor(arg.getParentRegion()));
    return Same{entering[arg.getArgNumber()]};
  }
  return Made{};
}

// What counting and linearity make of an array changes which value names
// it, not which cell it is.
Value idr::arrayRoot(Value array) {
  return definitionChain(array, [](Value value) -> std::optional<Value> {
           Source source = sourceOf(value);
           if (auto *same = std::get_if<Same>(&source))
             return same->value;
           return std::nullopt;
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

ownership::Use idr::ownership::useOf(OpOperand &operand) {
  return effects::consumes(operand) ? Use::Consume : Use::Borrow;
}

namespace {

// One step up a view's chain: what `value` was read from, or the value it
// is (sourceOf's Same): the operand of an op that keeps its operand's
// value (a linear position), a loan's view, or a match region's refined
// operand. idr.count.share is not such an op: its result holds the
// reference its operand gave up, so a view of it is a view of the result.
std::optional<Value> viewedFrom(Value value) {
  if (Value from = ownership::readFrom(value))
    return from;
  Source source = sourceOf(value);
  if (const auto *same = std::get_if<Same>(&source))
    return same->value;
  return std::nullopt;
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
  Source source = sourceOf(value);
  if (const auto *field = std::get_if<Field>(&source))
    return field->scrutinee;
  // A view of a buffer lives while the buffer it views does. A counted
  // element is read from its buffer, which holds its reference. Each is
  // read off the operand itself, not the op's typed accessor: counting
  // grades a buffer a step before it gives each read of it the bare view
  // upstream's op takes, and the steps between ask what was read from what.
  // Every view-like op, upstream's and ours, takes its source first.
  if (auto view = value.getDefiningOp<ViewLikeOpInterface>(); view && view.getViewDest() == value)
    return view->getOperand(0);
  if (auto load = value.getDefiningOp<memref::LoadOp>();
      load && holdsReferences(load.getType()))
    return load.getMemrefMutable().get();
  return nullptr;
}

// The block arguments sourceOf calls the same value as another are a match
// region's refined operands and a loan's view; an op that keeps its
// operand's value (Idr_SameValue) is not followed here, as readFrom does
// not.
std::optional<Value> idr::ownership::readThrough(Value value) {
  if (Value from = readFrom(value))
    return from;
  Source source = sourceOf(value);
  if (const auto *same = std::get_if<Same>(&source); same && isa<BlockArgument>(value))
    return same->value;
  return std::nullopt;
}

// A view's chain goes up through what each step was read from and through
// the values each step is, to the value as it was made: it stops at a
// share, whose result holds a reference of its own.
Value idr::ownership::viewRoot(Value value) { return definitionChain(value, viewedFrom).back(); }
