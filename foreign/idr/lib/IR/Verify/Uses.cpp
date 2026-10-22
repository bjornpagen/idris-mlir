// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Which constructor has a cell, what a use does with a reference in the
// owned stage, and what a view was read from, by a value's structural
// source (sourceOf) and upstream's buffer views: shared by the ownership
// passes, so each has one meaning.

#include "idr/IR/Effects/Query.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Ownership.h"
#include "idr/IR/Symbols.h"

#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Interfaces/ViewLikeInterface.h"
#include "llvm/ADT/STLExtras.h"

#include <optional>

using namespace mlir;
using namespace idr;

bool idr::buildsCell(Type type, Tag tag) {
  DataType data = dataTypeOf(type);
  return data && data.layout() == Layout::Cell && !data.ctor(tag).fields.empty();
}

ownership::Use idr::ownership::useOf(OpOperand &operand) {
  return consumes(operand) ? Use::Consume : Use::Borrow;
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
