// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What the control-flow ops state of the lifetimes of the scoped values
// they make (StatesLifetimeOpInterface): a match's results and the refined
// values its regions bind, a join point's op's results and its join
// regions' parameters. Each op holds one `outer` lifetime operand, present
// exactly when a value it makes is scoped, so a value's lifetime is one hop
// from it, never a walk back to the operand it was refined from. One
// definition for the four ops, instantiated per op.
#ifndef IDR_IR_CONTROL_STATED_H
#define IDR_IR_CONTROL_STATED_H

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/Operation.h"
#include "mlir/IR/Value.h"
#include "llvm/ADT/STLExtras.h"

#include <concepts>

namespace idr::control {

// An op of ours that states one lifetime for every scoped value it makes.
template <typename Op>
concept StatesOuter = requires(Op op) {
  { op.getOuter() } -> std::convertible_to<mlir::Value>;
  op.getOuterMutable();
};

// Whether `value` lives in a lifetime.
inline bool scoped(mlir::Value value) { return freedBy(value.getType(), Release::Scoped); }

// Whether `op` made `value`: one of its results, or an argument of the
// entry block of one of its regions.
inline bool madeBy(mlir::Operation *op, mlir::Value value) {
  if (auto result = llvm::dyn_cast<mlir::OpResult>(value))
    return result.getOwner() == op;
  mlir::Block *block = llvm::cast<mlir::BlockArgument>(value).getOwner();
  return block->isEntryBlock() && block->getParentOp() == op;
}

// Whether `op` makes a scoped value.
inline bool makesScoped(mlir::Operation *op) {
  return llvm::any_of(op->getResults(), scoped) ||
         llvm::any_of(op->getRegions(), [](mlir::Region &region) {
           return !region.empty() && llvm::any_of(region.front().getArguments(), scoped);
         });
}

template <StatesOuter Op>
mlir::Value statedFor(Op op, mlir::Value made) {
  return scoped(made) && madeBy(op, made) ? mlir::Value(op.getOuter()) : mlir::Value();
}

template <StatesOuter Op>
void stateFor(Op op, mlir::Value made, mlir::Value lifetime) {
  if (madeBy(op, made))
    op.getOuterMutable().assign(lifetime);
}

// The operand is present exactly when a value the op makes is scoped: one
// that changes nothing is no flag, and a scoped value with no lifetime
// stated is one no check can place.
template <StatesOuter Op>
mlir::LogicalResult verifyStated(Op op) {
  bool any = makesScoped(op.getOperation());
  if (any != static_cast<bool>(op.getOuter()))
    return op.emitOpError(any ? "makes a scoped value but states no lifetime for it"
                              : "states a lifetime for values none of which is scoped");
  return mlir::success();
}

} // namespace idr::control

#endif // IDR_IR_CONTROL_STATED_H
