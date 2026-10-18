// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a use does with a reference in the owned stage, which values no
// count reaches, and what a view was read from, by a value's structural
// source (sourceOf) and upstream's buffer views: shared by the owned walk
// and the ownership passes, so each has one meaning.

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Ownership.h"
#include "idr/IR/Symbols.h"
#include "idr/IR/Verify.h"

#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/Matchers.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "mlir/Interfaces/ViewLikeInterface.h"
#include "llvm/ADT/STLExtras.h"

#include <optional>

using namespace mlir;
using namespace idr;

ownership::Use idr::ownership::useOf(OpOperand &operand) {
  return consumes(operand) ? Use::Consume : Use::Borrow;
}

namespace {

// One step up a view's chain: what `value` was read from, or the value it
// is (sourceOf's Same): the operand of an op that keeps its operand's
// value (a borrow, a linear position), or the scrutinee a match's default
// binds again. idr.share is not such an op: its result holds the
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

// An op that allocates nothing and reads no reference makes its value from
// nothing a count reaches: a constant, poison, a small big, a pending
// field, a global's buffer. What is read from such a value, or is such a
// value at another grade, is no more counted than it. An op with regions
// is no such op, whatever its operands: its value is what its regions
// yield, which they may read from above, and each yield takes the
// reference it forwards.
bool idr::ownership::isStatic(Value value) {
  return llvm::any_of(definitionChain(value, viewedFrom), [](Value at) {
    Operation *def = at.getDefiningOp();
    return def && def->getNumRegions() == 0 && isPure(def) &&
           llvm::none_of(def->getOperandTypes(), [](Type type) { return holdsReferences(type); });
  });
}

// A field is read from its constructor value (sourceOf's Field: an
// idr.field, a memo cell's part included, or an argument a match's case
// binds); a match's default binds its scrutinee again, the same value, and
// reads nothing from it. The flow edges are not asked: they also move a
// force's value and an array's element out of what holds them, which would
// make each a view of its cell, and carry nothing for a field that is a
// word.
Value idr::ownership::readFrom(Value value) {
  Source source = sourceOf(value);
  if (const auto *field = std::get_if<Field>(&source))
    return field->scrutinee;
  // A view of a buffer lives while the buffer it views does.
  if (auto view = value.getDefiningOp<ViewLikeOpInterface>(); view && view.getViewDest() == value)
    return view.getViewSource();
  // A counted element is read from its buffer, which holds its reference.
  if (auto load = value.getDefiningOp<memref::LoadOp>();
      load && holdsReferences(load.getType()))
    return load.getMemref();
  return nullptr;
}

// The one block argument sourceOf calls the same value as another is the
// argument a match's default region binds; an op that keeps its operand's
// value (Idr_SameValue) is not followed here, as readFrom does not.
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

namespace {

// Whether the constant `attr`, held as `type`, reaches no cell but atoms:
// a box of an atom; or a constructor held in place, one cell of it, whose
// fields reach none either; or a value that is no box or sum at all (a
// number, a static string or big, which nothing takes apart). A closure is
// a cell. A run of more than one cell, held in place or boxed, holds each
// cell after its first in a box at its spine, which has fields.
bool onlyAtoms(Attribute attr, Type type) {
  if (isa<ClosureAttr>(attr))
    return false;
  auto con = dyn_cast<ConAttr>(attr);
  if (!con)
    return true;
  if (isBoxed(type))
    return con.getData().isAtom(con.getTag());
  if (con.getRunLength() > 1)
    return false;
  ArrayRef<Type> fields = con.getCtor().fields;
  bool atoms = true;
  con.walkFields([&](Attribute field, unsigned index) {
    atoms = atoms && onlyAtoms(field, fields[index]);
  });
  return atoms;
}

} // namespace

// A constant atom (a box of a constructor with no fields, a static cell),
// or a constant sum held in place, which has no cell, whose fields reach
// none either (a pair of empty lists). Only idr.take hands out a cell, and
// only of a box whose constructor is not an atom; an atom's take and a
// sum's are idr.unpack, which hands out none. No count reaches such a
// constant, nothing frees or writes it, so whoever else holds it changes
// nothing a consumer of exclusivity does. A static box with fields is not
// one: its take would hand out its cell as a token to build in.
bool idr::ownership::reachesOnlyAtoms(Value view) {
  Attribute attr;
  return matchPattern(view, m_Constant(&attr)) && onlyAtoms(attr, unrestricted(view.getType()));
}
