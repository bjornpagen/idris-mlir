// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The one walk of a body that numbers what a marking decides about, used by
// the marking's extraction and by whoever writes its answer back, so the
// two meet on the same numbers with no map between them: blocks in
// pre-order, and in each block its arguments, then its ops' results, in
// order. A grade copy is a clone of its original, so the walk numbers its
// values as its original's.
#ifndef IDR_ANALYSIS_OWNERSHIP_WALKS_H
#define IDR_ANALYSIS_OWNERSHIP_WALKS_H

#include "idr/Analysis/Ownership/Facts.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/Block.h"
#include "mlir/IR/Value.h"
#include "mlir/IR/Visitors.h"

#include <concepts>
#include <cstdint>

namespace idr::ownership {

// Every value of `fn`'s body, in the walk's order, with the block it is in.
template <typename Each>
  requires std::invocable<Each &, mlir::Value>
void forEachValue(FuncOp fn, Each &&each) {
  fn->walk<mlir::WalkOrder::PreOrder>([&](mlir::Block *block) {
    for (mlir::BlockArgument arg : block->getArguments())
      each(mlir::Value(arg));
    for (mlir::Operation &op : *block)
      for (mlir::Value result : op.getResults())
        each(result);
  });
}

// Every call of `fn`'s body, in the walk's order.
template <typename Each>
  requires std::invocable<Each &, CallOp>
void forEachCall(FuncOp fn, Each &&each) {
  fn->walk<mlir::WalkOrder::PreOrder>([&](mlir::Block *block) {
    for (CallOp call : block->getOps<CallOp>())
      each(call);
  });
}

} // namespace idr::ownership

namespace idr::exclusivity {

// Whether exclusivity follows `value`: a counted value that holds
// references whose grade does not already say `unique deep`.
inline bool followed(mlir::Value value) {
  return ownership::leavesOpen(value.getType(), Unique::Deep);
}

// Every followed value of `fn`'s body, numbered from zero in the walk's
// order.
template <typename Each>
  requires std::invocable<Each &, mlir::Value, std::uint32_t>
void forEachFollowed(FuncOp fn, Each &&each) {
  std::uint32_t next = 0;
  ownership::forEachValue(fn, [&](mlir::Value value) {
    if (followed(value))
      each(value, next++);
  });
}

} // namespace idr::exclusivity

namespace idr::borrows {

// Whether `arg` is a join parameter: an argument of a region entered only by
// jumps, never by its parent's own entry, so each jump is a call of it.
bool isJoinParameter(mlir::BlockArgument arg);

// Every join parameter of `fn` that holds references, numbered from zero
// in the walk's order.
template <typename Each>
  requires std::invocable<Each &, mlir::BlockArgument, std::uint32_t>
void forEachJoinParameter(FuncOp fn, Each &&each) {
  std::uint32_t next = 0;
  ownership::forEachValue(fn, [&](mlir::Value value) {
    auto arg = llvm::dyn_cast<mlir::BlockArgument>(value);
    if (arg && holdsReferences(arg.getType()) && isJoinParameter(arg))
      each(arg, next++);
  });
}

} // namespace idr::borrows

#endif // IDR_ANALYSIS_OWNERSHIP_WALKS_H
