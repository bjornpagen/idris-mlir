// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a use does with a reference in the owned stage, which values no
// count reaches, and the one predicate the stage is decided by: shared by
// the owned walk and the ownership passes, so each has one meaning.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Ownership.h"
#include "idr/IR/Symbols.h"
#include "idr/IR/Verify.h"

#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/Matchers.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;
using namespace idr;

ownership::Use idr::ownership::useOf(OpOperand &operand, SymbolTable *symbols) {
  if (isa<ForceOp>(operand.getOwner()))
    return isOwned(operand.get().getType()) ? Use::Consume : Use::Borrow;
  return consumes(operand, symbols) ? Use::Consume : Use::Borrow;
}

bool idr::ownership::isStatic(Value value) {
  for (; value; value = readFrom(value)) {
    Operation *def = value.getDefiningOp();
    if (def && (def->hasTrait<OpTrait::ConstantLike>() || isa<ub::PoisonOp, BigSmallOp, PendingOp>(def)))
      return true;
  }
  return false;
}

Value idr::ownership::readFrom(Value value) {
  if (auto field = value.getDefiningOp<FieldOp>())
    return field.getValue();
  auto arg = dyn_cast<BlockArgument>(value);
  if (!arg)
    return nullptr;
  if (auto match = dyn_cast_or_null<MatchOp>(arg.getOwner()->getParentOp()))
    return match.getScrutinee();
  return nullptr;
}

Value idr::ownership::viewRoot(Value value) {
  for (;;) {
    if (Value from = readFrom(value)) {
      value = from;
      continue;
    }
    Operation *def = value.getDefiningOp();
    if (!isa_and_nonnull<BorrowOp, LinEnterOp, LinUseOp>(def))
      return value;
    value = def->getOperand(0);
  }
}

namespace {

// Whether the constant `attr` reaches no cell but atoms: a box constructor
// without fields, a constructor of an unboxed sum whose fields reach none
// either, or a value that is no box or sum at all (a number, a static
// string or big, which nothing takes apart). A closure is a cell. A run is
// read cell by cell and then its tail, never field by field along its
// spine, which would rebuild the rest of the run at every step: its cells
// hold every field but the one that links them.
bool onlyAtoms(Attribute attr, function_ref<DataOp(Type)> declaration) {
  if (isa<ClosureAttr>(attr))
    return false;
  auto con = dyn_cast<ConAttr>(attr);
  if (!con)
    return true;
  // The declaration depends on the name alone, so the type asked for is the
  // unboxed one whether the constructor's values are boxed or not.
  MLIRContext *ctx = attr.getContext();
  DataOp data = declaration(
      DataType::get(ctx, FlatSymbolRefAttr::get(con.getCtor().getRootReference())));
  if (!data)
    return false;
  // The cells of a run have at least the field that links them. A memo
  // cell is written by its first force, so it is never an atom, even in a
  // state without fields.
  if (data.getBox())
    return !isMemo(data) && !con.isRun() && con.getFields().empty();
  auto atoms = [&](ArrayAttr fields) {
    return llvm::all_of(fields, [&](Attribute field) { return onlyAtoms(field, declaration); });
  };
  return llvm::all_of(con.getCells(), atoms) && (!con.isRun() || onlyAtoms(con.getTail(), declaration));
}

} // namespace

// A constant nullary constructor (an atom, a static cell with no fields),
// or a constant unboxed sum, which has no cell, whose fields reach none
// either (a pair of empty lists). No take hands out a cell of it, since an
// atom has no fields to take and a sum no cell; no count reaches it,
// nothing frees or writes it. So whoever else holds it changes nothing a
// consumer of exclusivity does. A static box with fields is not: a take of
// it would hand out its cell as a token to build in.
bool idr::ownership::reachesOnlyAtoms(Value view, function_ref<DataOp(Type)> declaration) {
  Attribute attr;
  return matchPattern(view, m_Constant(&attr)) && onlyAtoms(attr, declaration);
}

// The body says that it runs again by being its own successor. A body that
// only crashes has no such edge, because ub.unreachable is not a
// region-branch terminator, and still covers each index up to the crash.
bool idr::ownership::isArrayLoop(Operation *op) {
  if (!isa<ArrayGenerateOp, ArrayFoldOp>(op) || op->getRegion(0).empty())
    return false;
  Block &body = op->getRegion(0).front();
  if (!body.empty() && isa<ub::UnreachableOp>(body.getTerminator()))
    return true;
  return cast<RegionBranchOpInterface>(op).isRepetitiveRegion(0);
}

// One walk, which stops at the first owned value.
bool idr::ownership::inOwnedStage(FuncOp fn) {
  return fn->walk([](Operation *op) {
             return verify::definesOwned(op) ? WalkResult::interrupt() : WalkResult::advance();
           })
      .wasInterrupted();
}

bool idr::verify::definesOwned(Operation *op) {
  auto owned = [](Value value) { return isOwned(value.getType()); };
  if (llvm::any_of(op->getResults(), owned))
    return true;
  for (Region &region : op->getRegions())
    for (Block &block : region)
      if (llvm::any_of(block.getArguments(), owned))
        return true;
  return false;
}
