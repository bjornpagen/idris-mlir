// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The types of one function's conversion and the one materialization
// between them.
//
// A closure's or a suspension's type is its plan's, its key's sum: a
// carrier has no type of its own without the slot that holds it. Any other
// type is itself; the types that hold a slot are made anew once every
// function has converted.
//
// Where a value moves between slots of two keys (an operand into the slot
// its op moves it to, and through a dispatch into and out of a label), the
// patterns ask for the target materialization: a match that rebuilds each
// constructor of the one sum in the other, whose labels hold the first's,
// each label found by the function its constructor names.
// No source materialization exists: a value left in its old type is one
// nothing lowers, so a conversion that needs one fails.

#include "idr/IR/IdrDialect.h"
#include "idr/Analysis/Labels.h"
#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Symbols.h"
#include "idr/Transforms/Defunctionalize.h"

#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/Builders.h"
#include "mlir/Transforms/DialectConversion.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"

#include <optional>

using namespace mlir;

namespace idr::defunctionalize {

namespace {

// `value`, a value of one closure sum, as a value of the closure sum `to`:
// a match over its constructors, each case binding the fields at the
// scrutinee's grade and building the constructor of `to` that names the
// same function, with them held as its fields. Null, with nothing built,
// when `to` lacks one of them. A memo sum's cell is never rebuilt: the copy
// would not be the cell its other holders force.
Value rebuildIn(OpBuilder &b, Location loc, Type to, Value value) {
  Type from = value.getType();
  DataType source = dataTypeOf(from), target = dataTypeOf(to);
  if (!source || !target || !source.isClosures() || !target.isClosures())
    return nullptr;
  llvm::DenseMap<Attribute, Tag> tagOf;
  for (auto [tag, ctor] : llvm::zip_equal(target.getTags(), target.getCtors()))
    tagOf.try_emplace(ctor.fn, tag);
  ArrayRef<Ctor> ctors = source.getCtors();
  SmallVector<Tag> tags;
  for (const Ctor &ctor : ctors) {
    auto it = tagOf.find(ctor.fn);
    if (it == tagOf.end() || target.getCtor(it->second).fields.size() != ctor.fields.size())
      return nullptr;
    tags.push_back(it->second);
  }
  OpBuilder::InsertionGuard guard(b);
  auto cases = llvm::to_vector(source.getTags());
  auto made = MatchOp::create(b, loc, TypeRange{to}, value, ArrayRef<Tag>(cases),
                              static_cast<unsigned>(ctors.size()));
  for (auto [ctor, tag, region] : llvm::zip_equal(ctors, tags, made.getRegions())) {
    SmallVector<Type> bound;
    for (Type field : ctor.fields)
      bound.push_back(fieldType(from, field));
    Block *block =
        b.createBlock(&region, region.end(), bound, SmallVector<Location>(bound.size(), loc));
    SmallVector<Value> held;
    for (auto [arg, type] : llvm::zip_equal(block->getArguments(), target.getCtor(tag).fields))
      held.push_back(heldAs(b, loc, arg, type));
    Value rebuilt = ConOp::create(b, loc, to, tag, held).getResult();
    YieldOp::create(b, loc, rebuilt);
  }
  return made.getResult(0);
}

// A linear value is used once, rebuilt, and enters the other linear slot.
Value rebuild(OpBuilder &b, Type to, Value value, Location loc) {
  Type from = value.getType();
  if (isLinear(from) != isLinear(to))
    return nullptr;
  if (!isLinear(from))
    return rebuildIn(b, loc, to, value);
  Value used = LinUseOp::create(b, loc, unrestricted(from), value);
  Value moved = rebuildIn(b, loc, unrestricted(to), used);
  if (!moved)
    return nullptr;
  return LinEnterOp::create(b, loc, to, moved);
}

} // namespace

SlotTypeConverter::SlotTypeConverter(const Slots &slots, const Plan &plan)
    : decision(slots), own(plan) {
  // The most recently added conversion is tried first. The type alone
  // answers every type that is no closure or suspension, itself; it
  // declines a carrier, and the value's plan answers.
  addConversion([this](Value value, SmallVectorImpl<Type> &out) -> std::optional<LogicalResult> {
    out.push_back(typeOf(value));
    return success();
  });
  addConversion([](Type type) -> std::optional<Type> {
    if (carriesLabels(type))
      return std::nullopt;
    return type;
  });
  addTargetMaterialization([](OpBuilder &b, Type to, ValueRange inputs, Location loc) -> Value {
    if (inputs.size() != 1)
      return nullptr;
    return rebuild(b, to, inputs.front(), loc);
  });
}

Type SlotTypeConverter::typeOf(Value value) const {
  auto it = own.types.find(value);
  return it == own.types.end() ? value.getType() : it->second;
}

Slot SlotTypeConverter::keyOf(Value value) const {
  auto it = own.keys.find(value);
  return it == own.keys.end() ? Slot() : Slot(it->second);
}

Slot SlotTypeConverter::sinkKey(OpOperand &use) const {
  auto it = own.sinks.find(&use);
  return it == own.sinks.end() ? Slot() : Slot(it->second);
}

bool SlotTypeConverter::legal(Operation *op) const {
  // Only a use the function had has a slot to move into; a use the
  // conversion made was made with its value already moved.
  for (OpOperand &use : op->getOpOperands()) {
    if (!legal(use.get()))
      return false;
    if (needsCoercion(keyOf(use.get()), sinkKey(use)))
      return false;
  }
  if (!llvm::all_of(op->getResults(), [&](Value result) { return legal(result); }))
    return false;
  for (Region &region : op->getRegions())
    for (Block &block : region)
      if (!llvm::all_of(block.getArguments(), [&](Value arg) { return legal(arg); }))
        return false;
  return true;
}

// A value no slot ever holds, or one moving into a slot no label reaches,
// is a move that never runs: the program's poison, as any poison is.
Value SlotTypeConverter::coerce(OpBuilder &b, Location loc, Value value, const Slot &from,
                                const Slot &to, Type sink) const {
  if (!needsCoercion(from, to))
    return value;
  if (from->isEmpty() || to->isEmpty())
    return ub::PoisonOp::create(b, loc, sink);
  return materializeTargetConversion(b, loc, sink, value);
}

Value SlotTypeConverter::coerceOperand(OpBuilder &b, OpOperand &use, Value remapped) const {
  Slot to = sinkKey(use);
  if (!to)
    return remapped;
  return coerce(b, use.getOwner()->getLoc(), remapped, keyOf(use.get()), to,
                decision.typeOf(use.get().getType(), to));
}

LogicalResult SlotTypeConverter::coerceOperands(OpBuilder &b, Operation *op, ValueRange remapped,
                                                SmallVectorImpl<Value> &out) const {
  for (auto [use, value] : llvm::zip_equal(op->getOpOperands(), remapped)) {
    Value moved = coerceOperand(b, use, value);
    if (!moved)
      return failure();
    out.push_back(moved);
  }
  return success();
}

} // namespace idr::defunctionalize
