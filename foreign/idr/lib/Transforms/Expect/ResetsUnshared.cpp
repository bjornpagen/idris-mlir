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

#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::expect {

namespace {

// What `op` declares of the count of `value`, by kind, read through the
// effect system's terms for each of MLIR's effect instances.
bool onCountOf(Operation *op, Value value, effects::Kind kind) {
  auto declares = dyn_cast<MemoryEffectOpInterface>(op);
  if (!declares)
    return false;
  SmallVector<MemoryEffects::EffectInstance> instances;
  declares.getEffects(instances);
  return llvm::any_of(instances, [&](const MemoryEffects::EffectInstance &instance) {
    effects::Effect each = effects::effectOf(instance);
    return each.kind == kind && each.resource == effects::ResourceId::Count && each.value == value;
  });
}

// Whether a value of `type` is what a test gives for what it took apart:
// the cell, or the token that holds it.
bool givenForReuse(Type type) {
  Type carrier = unrestricted(type);
  return isa<CellType, TokenType>(carrier);
}

// Whether `operand`'s op tests the sharing of its value: it reads the
// count of a value it consumes, and gives a cell or a token, as a result or
// to a region it runs.
bool testsSharing(OpOperand &operand) {
  Operation *op = operand.getOwner();
  if (!effects::consumes(operand) || !onCountOf(op, operand.get(), effects::Kind::Read))
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
      return !effects::consumes(use) && onCountOf(use.getOwner(), view, effects::Kind::Write);
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
