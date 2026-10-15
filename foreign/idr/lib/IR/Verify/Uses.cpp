// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a use does with a reference in the owned stage, which values no
// count reaches, and what a view was read from: shared by the owned walk
// and the ownership passes, so each has one meaning.

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Ownership.h"
#include "idr/IR/Symbols.h"
#include "idr/IR/Verify.h"

#include "mlir/Dialect/Linalg/IR/Linalg.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/Matchers.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "mlir/Interfaces/ViewLikeInterface.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;
using namespace idr;

ownership::Use idr::ownership::useOf(OpOperand &operand, SymbolTable *symbols) {
  return consumes(operand, symbols) ? Use::Consume : Use::Borrow;
}

// An op that allocates nothing and reads no reference makes its value from
// nothing a count reaches: a constant, poison, a small big, a pending
// field, a global's buffer. What is read from such a value, or is such a
// value at another grade, is no more counted than it.
bool idr::ownership::isStatic(Value value) {
  while (value) {
    Operation *def = value.getDefiningOp();
    if (def && isPure(def) &&
        llvm::none_of(def->getOperandTypes(), [](Type type) { return holdsReferences(type); }))
      return true;
    if (Value from = readFrom(value)) {
      value = from;
      continue;
    }
    value = def && def->hasTrait<ResultCarriesOperand>() ? def->getOperand(0) : Value();
  }
  return false;
}

Value idr::ownership::readFrom(Value value) {
  if (auto field = value.getDefiningOp<FieldOp>())
    return field.getValue();
  // A view of a buffer lives while the buffer it views does.
  if (auto view = value.getDefiningOp<ViewLikeOpInterface>(); view && view.getViewDest() == value)
    return view.getViewSource();
  // A counted element is read from its buffer, which holds its reference.
  if (auto load = value.getDefiningOp<memref::LoadOp>();
      load && holdsReferences(load.getType()))
    return load.getMemref();
  auto arg = dyn_cast<BlockArgument>(value);
  if (!arg)
    return nullptr;
  if (auto match = dyn_cast_or_null<MatchOp>(arg.getOwner()->getParentOp()))
    return match.getScrutinee();
  return nullptr;
}

// A view's chain goes up through what each step was read from and through
// the ops that only change a grade (a borrow, a linear position), to the
// value as it was made. Each step is to a value defined before it, so the
// chain ends.
Value idr::ownership::viewRoot(Value value) {
  for (;;) {
    if (Value from = readFrom(value)) {
      value = from;
      continue;
    }
    Operation *def = value.getDefiningOp();
    if (!def || !def->hasTrait<ResultCarriesOperand>())
      return value;
    value = def->getOperand(0);
  }
}

namespace {

// Whether the constant `attr`, held as `type`, reaches no cell but atoms: a
// box constructor without fields, a constructor held in place whose fields
// reach none either, or a value that is no box or sum at all (a number, a
// static string or big, which nothing takes apart). A closure is a cell. A
// run is read cell by cell and then its tail, never field by field along
// its spine, which would rebuild the rest of the run at every step: its
// cells hold every field but the one that links them, and its tail is held
// as the run is.
bool onlyAtoms(Attribute attr, Type type) {
  if (isa<ClosureAttr>(attr))
    return false;
  auto con = dyn_cast<ConAttr>(attr);
  if (!con)
    return true;
  DataType data = con.getData();
  // The cells of a run have at least the field that links them. A memo
  // cell is written by its first force, so it is never an atom, even in a
  // state without fields.
  if (isBoxed(type))
    return !data.isMemo() && !con.isRun() && con.getFields().empty();
  SmallVector<Type> fields(data.getCtor(con.getTag()).fields);
  if (con.isRun())
    fields.erase(fields.begin() + con.getSpine());
  auto atoms = [&](ArrayAttr cell) {
    return llvm::all_of(llvm::zip_equal(cell, fields), [](auto field) {
      return onlyAtoms(std::get<0>(field), std::get<1>(field));
    });
  };
  return llvm::all_of(con.getCells(), atoms) && (!con.isRun() || onlyAtoms(con.getTail(), type));
}

} // namespace

// A constant nullary constructor (an atom, a static cell with no fields),
// or a constant sum held in place, which has no cell, whose fields reach
// none either (a pair of empty lists). No take hands out a cell of it,
// since an atom has no fields to take and a sum no cell; no count reaches
// it, nothing frees or writes it. So whoever else holds it changes nothing
// a consumer of exclusivity does. A static box with fields is not: a take
// of it would hand out its cell as a token to build in.
bool idr::ownership::reachesOnlyAtoms(Value view) {
  Attribute attr;
  return matchPattern(view, m_Constant(&attr)) && onlyAtoms(attr, unrestricted(view.getType()));
}

// A loop over indices runs its body once per index: an scf.for, and a
// structured op on buffers.
bool idr::ownership::isIndexLoop(Operation *op) {
  if (isa<scf::ForOp>(op))
    return true;
  auto structured = dyn_cast<linalg::LinalgOp>(op);
  return structured && structured.hasPureBufferSemantics();
}
