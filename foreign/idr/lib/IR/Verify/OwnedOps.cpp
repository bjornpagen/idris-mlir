// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The owned walk's visit of one op without regions: what it consumes and
// borrows, what it makes, and the rules of the ops that change a grade, of
// cells, of exclusive values, and of the boundary with upstream's buffer
// ops. A box whose constructor has fields is built in its cell once idr-rc
// has run: a source op gives the cell, which is owned, and the
// idr.cell.init that fills it consumes it. Where our grades meet upstream's
// buffer ops, which see plain values, a reference crosses on its own: an
// allocation's fresh reference rides its plain buffer until the
// idr.own.adopt that takes it over, an owned value's rides idr.own.give's
// plain result into the store that writes it, and an element loaded from a
// buffer is a view of the buffer until the idr.dup right after it gives it
// a reference of its own.

#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Ownership.h"
#include "idr/IR/Verify.h"

#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/Support/ErrorHandling.h"

using namespace mlir;
using namespace idr;

LogicalResult idr::verify::OwnedWalk::visit(Operation &op) {
  // idr-rc makes every cell explicit: past it, a box whose constructor has
  // fields is filled in its cell, never built as a value.
  if (auto con = dyn_cast<ConOp>(op); con && buildsCell(con.getResult().getType(), con.getTag()))
    return op.emitOpError("builds a box with fields as a value in the owned stage; idr-rc makes "
                          "its cell explicit (idr.cell.new and idr.cell.init)");
  if (op.hasTrait<ResultCarriesOperand>())
    return regrade(op);
  if (failed(loaded(op)) || failed(exclusive(op)))
    return failure();
  llvm::DenseSet<OpOperand *> forwarded;
  if (op.hasTrait<OpTrait::IsTerminator>())
    forwardedValues(&op, [&](OpOperand &operand, Value) { forwarded.insert(&operand); });
  if (failed(operands(op, forwarded)))
    return failure();
  SmallVector<Value> from = readBy(op, forwarded);
  for (Value result : op.getResults())
    if (failed(make(op, result, from)))
      return failure();
  return success();
}

// An op that only changes a grade (ResultCarriesOperand): its result is
// its operand's value. Where the op takes the operand's reference over, the
// reference moves into the result; where it does not (idr.borrow), the
// result is a view of the operand; a view at another grade (entered into a
// linear position, or used out of one) is a view of the same value.
LogicalResult idr::verify::OwnedWalk::regrade(Operation &op) {
  OpOperand &operand = op.getOpOperand(0);
  Value from = operand.get();
  Value to = op.getResult(0);
  switch (roleOf(from)) {
  case Role::Owned:
    if (ownership::useOf(operand) == ownership::Use::Consume) {
      if (failed(consume(op, from)))
        return failure();
      if (roleOf(to) == Role::Owned)
        set(to, 1);
      return success();
    }
    if (failed(use(op, from)))
      return failure();
    if (roleOf(to) == Role::Owned)
      return fail(op, from, "gives an owned value a second reference without taking its own; a "
                            "reference of its own is idr.dup's");
    viewOf(to, from);
    return success();
  case Role::Carried:
    return fail(op, from, "uses a reference on its way into a grade or a buffer; only the "
                          "idr.own.adopt that takes it over, or the store it is given to, uses it");
  case Role::View:
    if (failed(use(op, from)))
      return failure();
    if (roleOf(to) == Role::Owned)
      return fail(op, from, "gives a view, which holds no reference, an owned grade; a reference "
                            "of its own is idr.dup's");
    if (roleOf(to) == Role::View)
      viewOf(to, from);
    return success();
  case Role::Untracked:
    if (roleOf(to) == Role::Owned)
      set(to, 1);
    return success();
  }
  llvm_unreachable("a role");
}

// A counted element an op of upstream's reads out of memory (memref.load)
// is a view of the buffer, which a store into the buffer may release while
// the view lives: its one use is the idr.dup right after it, which gives it
// a reference of its own.
LogicalResult idr::verify::OwnedWalk::loaded(Operation &op) {
  if (isa_and_nonnull<IdrDialect>(op.getDialect()) || !hasEffect<MemoryEffects::Read>(&op))
    return success();
  for (Value result : op.getResults()) {
    if (roleOf(result) != Role::View)
      continue;
    auto dup = dyn_cast_or_null<DupOp>(op.getNextNode());
    if (!result.hasOneUse() || !dup || dup.getValue() != result)
      return fail(op, result, "reads an element that holds references out of memory, whose one "
                              "use is not the idr.dup right after it");
  }
  return success();
}

// An exclusive value alone reaches its cells: no view of it (or of what
// was read from it) takes a reference of its own, and an exclusive
// constructor is built of exclusive fields, never in a cell of the frame,
// which the frame lends. A reference of its own is exclusive only to
// static data that reaches no cell but atoms, which no take hands out: of
// anything else, the copy shares the original's cells. A constructor is
// built by idr.cell.init, which fills a cell, or by idr.con, which builds
// one that has none (an unboxed sum, an atom): two ops, as buildsCell
// decides, and each holds its fields to the rule.
LogicalResult idr::verify::OwnedWalk::exclusive(Operation &op) {
  if (auto dup = dyn_cast<DupOp>(op)) {
    if (isExclusive(dup.getType()) && !ownership::reachesOnlyAtoms(dup.getValue()))
      return fail(op, dup.getValue(), "takes an exclusive reference to a value that reaches "
                                      "cells other than atoms, which it shares");
    Value root = ownership::viewRoot(dup.getValue());
    if (isExclusive(root.getType()))
      for (OpOperand &use : root.getUses())
        if (!isa<ShareOp>(use.getOwner()) && ownership::useOf(use) == ownership::Use::Consume)
          return fail(op, root, "takes a reference to a view of an exclusive value, which "
                                "is then consumed as exclusive (idr.share gives it on as "
                                "owned)");
  }
  auto ofExclusives = [&](ValueRange fields) -> LogicalResult {
    for (Value field : fields) {
      auto dup = field.getDefiningOp<DupOp>();
      if (isOwned(field.getType()) && !isExclusive(field.getType()) &&
          isa<BoxType, DataType>(unrestricted(field.getType())) &&
          !(dup && ownership::reachesOnlyAtoms(dup.getValue())))
        return fail(op, field, "builds an exclusive value of a field that may be shared");
    }
    return success();
  };
  if (auto init = dyn_cast<CellInitOp>(op); init && isExclusive(init.getResult().getType())) {
    if (init.getCell().getDefiningOp<CellStackOp>())
      return op.emitOpError("builds an exclusive value in a cell of the frame, which is lent");
    return ofExclusives(init.getFields());
  }
  if (auto con = dyn_cast<ConOp>(op); con && isExclusive(con.getResult().getType()))
    return ofExclusives(con.getFields());
  return success();
}

// What an op does with each operand: an owned value is consumed, never
// read directly (a view of it, idr.borrow, is); a view is read, never
// consumed (a reference of its own, idr.dup, is); a reference on its way
// across the boundary is taken at its one use. An operand `forwarded`
// moves on with what it holds: an owned value's reference, or a view to be
// read beyond. What the op borrows must be alive for all of it, after what
// it consumes; one that passes values on passes its views on beside the
// references their owners move on with, so it reads them before the moves.
LogicalResult idr::verify::OwnedWalk::operands(Operation &op,
                                               const llvm::DenseSet<OpOperand *> &forwarded) {
  SmallVector<Value> consumed, borrowed;
  for (OpOperand &operand : op.getOpOperands()) {
    Value value = operand.get();
    bool moves = forwarded.contains(&operand);
    switch (roleOf(value)) {
    case Role::Carried:
      if (!takesCarried(operand))
        return fail(op, value, "uses a reference on its way into a grade or a buffer; only the "
                               "idr.own.adopt that takes it over, or the store it is given to, "
                               "uses it");
      consumed.push_back(value);
      break;
    case Role::Owned:
      if (!moves && ownership::useOf(operand) != ownership::Use::Consume)
        return fail(op, value, "reads an owned value; only a view of it (idr.borrow) is read");
      consumed.push_back(value);
      break;
    case Role::View:
      if (!moves && (ownership::useOf(operand) == ownership::Use::Consume ||
                     ownership::storedBy(operand)))
        return fail(op, value, "consumes a view, which holds no reference; a reference of "
                               "its own (idr.dup) is consumed, and an owned value's is given "
                               "to a store (idr.own.give)");
      borrowed.push_back(value);
      break;
    case Role::Untracked:
      break;
    }
  }
  bool passesOn = !forwarded.empty();
  if (passesOn)
    for (Value value : borrowed)
      if (failed(use(op, value)))
        return failure();
  for (Value value : consumed)
    if (failed(consume(op, value)))
      return failure();
  if (!passesOn)
    for (Value value : borrowed)
      if (failed(use(op, value)))
        return failure();
  return success();
}

// A reference crossing the boundary moves on at its one use: into the
// grade of the idr.own.adopt that takes a fresh buffer over, or into the
// memory an op of upstream's stores it in.
bool idr::verify::OwnedWalk::takesCarried(OpOperand &operand) {
  return isa<OwnAdoptOp>(operand.getOwner()) || ownership::storedBy(operand);
}

// The values `op` reads without taking them over or passing them on: what
// a view it makes was read from.
SmallVector<Value> idr::verify::OwnedWalk::readBy(Operation &op,
                                                  const llvm::DenseSet<OpOperand *> &forwarded) {
  SmallVector<Value> from;
  for (OpOperand &operand : op.getOpOperands())
    if (!forwarded.contains(&operand) && roleOf(operand.get()) == Role::View &&
        !llvm::is_contained(from, operand.get()))
      from.push_back(operand.get());
  return from;
}

// A value an op makes, not one it is forwarded: an owned value holds its
// own reference, a cell included; a Carried one, a buffer the op allocates
// or idr.own.give's result, holds the reference its plain type cannot say,
// until its one use takes it over; and a view is a view of what the op
// read (`from`), alive while each of those is.
LogicalResult idr::verify::OwnedWalk::make(Operation &op, Value value, ArrayRef<Value> from) {
  switch (roleOf(value)) {
  case Role::Owned:
  case Role::Carried:
    set(value, 1);
    return success();
  case Role::View:
    if (from.empty())
      return fail(op, value, "makes a value that holds references, which neither holds one of "
                             "its own nor is read from a value that does");
    viewOf(value, from);
    return success();
  case Role::Untracked:
    return success();
  }
  llvm_unreachable("a role");
}
