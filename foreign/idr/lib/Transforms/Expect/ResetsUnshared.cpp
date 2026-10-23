// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// resets-unshared: every run-time test of sharing finds its cell unshared,
// as far as the function shows: no value it tests is one the function gave
// another reference. Both are what the effect system's declarations say of
// each operand: a test reads the count of a value it consumes and gives a
// cell or a reuse token for what it took apart; another reference is a
// write of a value's count by an op that does not consume it.

#include "idr/Transforms/Expect.h"

#include "idr/IR/Effects/Classify.h"
#include "idr/IR/Effects/Consumption.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Ownership.h"
#include "idr/Support/Match.h"

#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::expect {

namespace {

// What `op` itself does, by kind, to the count of `value`, read through the
// effect system's one step over an op's own effects: an effect on the
// count of that value, or on every count (no value named, or a state the
// count is part of), touches it, and so does an op that says nothing MLIR
// can read, which may do anything. A use inside the op's regions is a use
// of its own, which the property reads at its own op.
effects::Does onCountOf(Operation *op, Value value, effects::Kind kind) {
  effects::Walked walked = effects::eachOwnEffect(op, [&](const effects::Effect &each) {
    bool touches = each.kind == kind &&
                   effects::atOrAbove[effects::ResourceId::Count].contains(each.resource) &&
                   (!each.value || each.value == value);
    return touches ? effects::Walked::Stopped : effects::Walked::All;
  });
  return walked == effects::Walked::Stopped ? effects::Does::Touches : effects::Does::Avoids;
}

// Whether a value of `type` is what a test gives for what it took apart:
// the cell, or the token that holds it. These are counting's two kinds of a
// cell's memory, and no value fact says "a cell's memory": the cell holds
// nothing yet and is used once by its type, while the token holds its cell,
// counted, at the uses its grade says. So the two are named here, the one
// place that asks.
bool givenForReuse(Type type) {
  Type carrier = unrestricted(type);
  return isa<CellType, ReuseTokenType>(carrier);
}

// Whether `operand`'s op tests the sharing of its value: it reads the
// count of a value it consumes, and gives a cell or a token, as a result or
// to a region it runs.
bool testsSharing(OpOperand &operand) {
  Operation *op = operand.getOwner();
  if (!effects::consumes(operand) ||
      onCountOf(op, operand.get(), effects::Kind::Read) == effects::Does::Avoids)
    return false;
  if (llvm::any_of(op->getResultTypes(), givenForReuse))
    return true;
  for (Region &region : op->getRegions())
    for (Block &block : region)
      if (llvm::any_of(block.getArgumentTypes(), givenForReuse))
        return true;
  return false;
}

// Whether the function gives `value` another reference: an op writes the
// count of it, or of the value it is the same as (sourceOf: the value it
// moved in from, a match's refined scrutinee), or of a value it was read
// from, whose cell then holds it shared, and does not consume it.
bool givenAnotherReference(Value value) {
  auto referenced = [](Value view) {
    return llvm::any_of(view.getUses(), [&](OpOperand &use) {
      return !effects::consumes(use) &&
             onCountOf(use.getOwner(), view, effects::Kind::Write) == effects::Does::Touches;
    });
  };
  for (; value; value = ownership::readFrom(value))
    for (Value alias = value; alias;) {
      if (referenced(alias))
        return true;
      alias = match(
          sourceOf(alias), [](const Same &same) { return same.value; },
          [](OneOf<Made, Field> auto &&) { return Value(); });
    }
  return false;
}

} // namespace

LogicalResult resetsUnshared(const Request<Roots> &request) {
  bool held = true;
  for (Operation *root : request.argument.roots(request.module))
    root->walk([&](Operation *op) {
      for (OpOperand &operand : op->getOpOperands()) {
        if (!testsSharing(operand) || !givenAnotherReference(operand.get()))
          continue;
        fail(op->getLoc(), request.property)
            << op->getName() << " in " << where(op)
            << " tests a cell that its function gives another reference";
        held = false;
      }
    });
  return success(held);
}

} // namespace idr::expect
