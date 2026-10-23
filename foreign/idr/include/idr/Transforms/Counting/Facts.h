// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What counting's passes share (lib/Transforms/Counting), read once from
// the types, the moves ops declare and upstream's control-flow interfaces:
// what its type says of a value's constructor, which values are elements
// read out of memory and left there, how a terminator leaves its region,
// and how often a region op runs its regions. Who frees a value is its
// hold's release (Grades.h), read where it is asked and never restated
// here. Each answer is a choice of an enum, so no pass asks a second
// question to learn what the first one meant.
#ifndef IDR_TRANSFORMS_COUNTING_FACTS_H
#define IDR_TRANSFORMS_COUNTING_FACTS_H

#include "idr/IR/Families/Declaration.h"
#include "idr/IR/Families/Families.h"
#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Lifetimes.h"
#include "idr/IR/Ownership.h"
#include "idr/IR/Traits.h"

#include "mlir/IR/Block.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/Value.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "llvm/ADT/STLExtras.h"

#include <cstdint>
#include <iterator>
#include <optional>

namespace idr::counting {

// The constructor a value's type fixes, when it fixes one: a case of a
// match binds its scrutinee refined to it, and a field is read only of
// such a value.
inline std::optional<Tag> knownConstructor(mlir::Type type) {
  auto data = llvm::dyn_cast<DataType>(unrestricted(type));
  if (!data)
    return std::nullopt;
  return data.singleTag();
}

// Whether a value of `type` is a memo cell: the one cell that changes
// while references to it live, as a force writes its state, so its
// constructor is no fact under a match and it is never taken apart.
inline bool isMemo(mlir::Type type) {
  auto data = llvm::dyn_cast<DataType>(unrestricted(type));
  return data && data.memo().has_value();
}

// Whether `op` gives its first operand back as its first result, the same
// reference at another grade (a cast between uses, a share) or at the end
// of a loan of it: the result carries what the operand held, so a counted
// operand moves into it.
inline bool givesOperandBack(mlir::Operation *op) {
  return op->hasTrait<ResultCarriesOperand>() || op->hasTrait<RunsOnceGivingBack>();
}

// The buffer `value` is read out of as an element and left in: a part read
// with no reference of its own (ownership::ownerOfPart) whose owner is
// memory, whose one anchor is its elements. A load and an array's read,
// upstream's and ours alike. None for any other value, and none for a
// region's argument bound to an element (a generating op's accumulator):
// its op binds it afresh in each run of its region, which the reading of a
// use within one block does not measure, so it stays the owned value
// counting places. The slot keeps its reference while nothing overwrites
// it, so the element holds one of its own only where counting gives it one.
inline std::optional<mlir::Value> elementBufferOf(mlir::Value value) {
  if (!llvm::isa<mlir::OpResult>(value))
    return std::nullopt;
  std::optional<mlir::Value> owner = ownership::ownerOfPart(value);
  if (!owner || !llvm::isa<mlir::BaseMemRefType>(unrestricted(owner->getType())))
    return std::nullopt;
  return owner;
}

// Whether `value`, which ownership::readFrom reads out of another (always
// an op's result), is read with no reference of its own: the op that reads
// it declares it a part (ownership::ownerOfPart), or declares no moves at
// all (a view upstream's op makes, its source's own words), or it is a loan
// to upstream's ops, a reference of no one's whose holder keeps its own. A
// field read whose slot is laid out apart from its type and whose re-pack
// builds a fresh cell or array declares its result fresh, and that result
// holds what it holds on its own, as any value made fresh does.
inline bool readWithoutReference(mlir::Value value) {
  return !declaresFlow(value.getDefiningOp()) || ownership::ownerOfPart(value).has_value() ||
         lifetimes::loanOf(value);
}

// How a terminator leaves its region: out of the function (its body's
// return), out of the process (a crash, an exit, an unreachable end: no
// successor at all), or to the successors upstream's region-branch
// interfaces name (a yield, a jump), which may be regions or ops around
// it.
enum class Leaves : std::uint8_t { Frame, Process, Successors };

// The return is asked first: it is return-like, which upstream makes a
// region-branch terminator too, but its parent is the function, no region
// branch, so it has no successors to ask. Its op's parent is always the
// function, which its verifier holds.
inline Leaves leavesOf(mlir::Operation *terminator) {
  if (llvm::isa<ReturnOp>(terminator))
    return Leaves::Frame;
  if (llvm::isa<mlir::RegionBranchTerminatorOpInterface>(terminator))
    return Leaves::Successors;
  return Leaves::Process;
}

// How often a region op runs its regions: each run enters exactly one of
// them once (a match, a join point's body and its join regions, a loan),
// so a value from outside moves into each; or any number of times or none
// (a loop, a branch that may skip its region, an op that declares no
// region branching), so a value from outside is held across the op and
// only read inside.
enum class Runs : std::uint8_t { Once, Repeats };

inline Runs runsOf(mlir::Operation *op) {
  auto branch = llvm::dyn_cast<mlir::RegionBranchOpInterface>(op);
  if (!branch || branch.hasLoop())
    return Runs::Repeats;
  llvm::SmallVector<mlir::RegionSuccessor> entries;
  branch.getSuccessorRegions(mlir::RegionBranchPoint::parent(), entries);
  if (entries.empty() ||
      llvm::any_of(entries, [](const mlir::RegionSuccessor &s) { return s.isOperation(); }))
    return Runs::Repeats;
  return Runs::Once;
}

// A point between two ops of a block, held as the position right after it:
// the op that follows it. A point is taken where the walk decides, on the
// function as it came, and every op put there goes right before that
// position, which nothing moves, so the ops put at one point keep the order
// they were put in, and no record of what went there before is kept.
struct Where {
  mlir::Block *block;
  mlir::Block::iterator next;

  static Where atStart(mlir::Block &block) { return {&block, block.begin()}; }
  static Where past(mlir::Operation *op) { return {op->getBlock(), std::next(op->getIterator())}; }
  static Where before(mlir::Operation *op) { return {op->getBlock(), op->getIterator()}; }
};

} // namespace idr::counting

#endif // IDR_TRANSFORMS_COUNTING_FACTS_H
