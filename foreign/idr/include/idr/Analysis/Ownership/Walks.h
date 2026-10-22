// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a marking decides about in a body, numbered in the solver's one
// walk of its values (solver::inWalkOrder), the walk every numbering of a
// body takes, used by the marking's extraction and by whoever writes its
// answer back, so the two meet on the same numbers with no map between
// them. A grade copy is a clone of its original, so the walk numbers its
// values as its original's.
#ifndef IDR_ANALYSIS_OWNERSHIP_WALKS_H
#define IDR_ANALYSIS_OWNERSHIP_WALKS_H

#include "idr/Analysis/Ownership/Facts.h"
#include "idr/Analysis/Solver/Extraction.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/Block.h"
#include "mlir/IR/Value.h"
#include "mlir/IR/Visitors.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <concepts>
#include <cstdint>

namespace idr::ownership {

// Every call of `fn`'s body, in the one order every reader of calls takes:
// blocks in pre-order, and each block's calls in order.
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
// references whose grade does not already say `unique deep`, and that is no
// element an op of upstream's reads out of an array. Such an op reads a loan
// of a value (idr.carrier), never the value, which keeps its grade; an
// element it reads out keeps the array's element type, which its own
// verifier holds it to, so it counts as shared and no step writes a grade
// into it.
inline bool followed(mlir::Value value) {
  return ownership::leavesOpen(value.getType(), Unique::Deep) &&
         !ownership::upstreamElement(value);
}

// Every followed value of `fn`'s body, numbered from zero in the walk's
// order.
template <typename Each>
  requires std::invocable<Each &, mlir::Value, std::uint32_t>
void forEachFollowed(FuncOp fn, Each &&each) {
  std::uint32_t next = 0;
  solver::inWalkOrder(fn, [&](mlir::Value value) {
    if (followed(value))
      each(value, next++);
  });
}

} // namespace idr::exclusivity

namespace idr::borrows {

// Whether `arg` is a join parameter: an argument of a region entered only by
// jumps, never by its parent's own entry, so each jump is a call of it.
inline bool isJoinParameter(mlir::BlockArgument arg) {
  mlir::Region *region = arg.getOwner()->getParent();
  auto branch = llvm::dyn_cast_or_null<mlir::RegionBranchOpInterface>(region->getParentOp());
  if (!branch || arg.getOwner() != &region->front())
    return false;
  llvm::SmallVector<mlir::RegionSuccessor> entries;
  branch.getSuccessorRegions(mlir::RegionBranchPoint::parent(), entries);
  return llvm::none_of(entries,
                       [&](mlir::RegionSuccessor &entry) { return entry.getSuccessor() == region; });
}

// Every join parameter of `fn` that holds references, numbered from zero
// in the walk's order.
template <typename Each>
  requires std::invocable<Each &, mlir::BlockArgument, std::uint32_t>
void forEachJoinParameter(FuncOp fn, Each &&each) {
  std::uint32_t next = 0;
  solver::inWalkOrder(fn, [&](mlir::Value value) {
    auto arg = llvm::dyn_cast<mlir::BlockArgument>(value);
    if (arg && holdsReferences(arg.getType()) && isJoinParameter(arg))
      each(arg, next++);
  });
}

} // namespace idr::borrows

#endif // IDR_ANALYSIS_OWNERSHIP_WALKS_H
