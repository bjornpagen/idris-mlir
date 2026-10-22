// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Which entry of `outers` states the lifetime of each scoped value a
// control-flow op's regions bind. A control op states one lifetime per
// scoped value it makes, its scoped results first, through the shared
// templates of lifetimes::StatesOuters (idr/IR/Lifetimes.h), which read
// the binding entries after the results' through the op's two members,
// getScopedBindings and getBindingEntry, defined here once per kind.
//
// A match's regions bind the same positions, the values entering each
// region refined at one hold, so one entry covers a position in every
// region; a position is scoped where some region's argument at it is,
// which keeps one entry while the decide step scopes a position's values
// one region at a time. A join point's op's regions bind values of their
// own, which arrive by different jumps: one entry for each, in region and
// argument order. Essential: the two kinds bind differently.
#ifndef IDR_IR_CONTROL_STATED_H
#define IDR_IR_CONTROL_STATED_H

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/Operation.h"
#include "mlir/IR/Value.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/Sequence.h"

#include <algorithm>
#include <cstddef>
#include <optional>

namespace idr::control {

// Whether `value` lives in a lifetime.
inline bool scoped(mlir::Value value) { return freedBy(value.getType(), Release::Scoped); }

// An op whose regions bind the same positions: a match, read off its ODS
// interface.
template <typename Op>
inline constexpr bool bindsPositions = Op::template hasTrait<MatchOpInterface::Trait>();

// The argument of `op`'s regions that `made` is, if it is one: an argument
// of the entry block of one of its regions.
inline std::optional<mlir::BlockArgument> boundBy(mlir::Operation *op, mlir::Value made) {
  auto arg = llvm::dyn_cast<mlir::BlockArgument>(made);
  if (!arg || !arg.getOwner()->isEntryBlock() || arg.getOwner()->getParentOp() != op)
    return std::nullopt;
  return arg;
}

// Whether some region of `op` binds a scoped argument at position `at`.
inline bool positionScoped(mlir::Operation *op, unsigned at) {
  return llvm::any_of(op->getRegions(), [&](mlir::Region &region) {
    return !region.empty() && at < region.getNumArguments() && scoped(region.getArgument(at));
  });
}

// How many positions `op`'s regions bind: the most arguments one binds.
inline unsigned positions(mlir::Operation *op) {
  unsigned most = 0;
  for (mlir::Region &region : op->getRegions())
    if (!region.empty())
      most = std::max(most, region.getNumArguments());
  return most;
}

// How many of `op`'s positions before `end` are scoped.
inline unsigned scopedPositions(mlir::Operation *op, unsigned end) {
  return static_cast<unsigned>(llvm::count_if(
      llvm::seq<unsigned>(0, end), [&](unsigned at) { return positionScoped(op, at); }));
}

// How many scoped arguments `op`'s regions bind before `end`, a region's
// entry argument or none for all of them.
inline unsigned scopedArguments(mlir::Operation *op, std::optional<mlir::BlockArgument> end) {
  unsigned count = 0;
  for (mlir::Region &region : op->getRegions()) {
    if (region.empty())
      continue;
    for (mlir::BlockArgument arg : region.getArguments()) {
      if (end && arg == *end)
        return count;
      count += scoped(arg) ? 1 : 0;
    }
  }
  return count;
}

// The entries the scoped values `op`'s regions bind take of its `outers`,
// after its scoped results'.
template <typename Op>
unsigned scopedBindings(Op op) {
  mlir::Operation *self = op.getOperation();
  if constexpr (bindsPositions<Op>)
    return scopedPositions(self, positions(self));
  else
    return scopedArguments(self, std::nullopt);
}

// The entry, counted from the first binding entry, of `made`, a value one
// of `op`'s regions binds, whether or not it is scoped yet; none for any
// other value.
template <typename Op>
std::optional<unsigned> bindingEntry(Op op, mlir::Value made) {
  mlir::Operation *self = op.getOperation();
  std::optional<mlir::BlockArgument> arg = boundBy(self, made);
  if (!arg)
    return std::nullopt;
  if constexpr (bindsPositions<Op>)
    return scopedPositions(self, arg->getArgNumber());
  else
    return scopedArguments(self, arg);
}

} // namespace idr::control

#endif // IDR_IR_CONTROL_STATED_H
