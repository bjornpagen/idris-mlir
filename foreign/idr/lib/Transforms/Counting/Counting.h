// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What counting's passes share, read once from the types and from
// upstream's control-flow interfaces: what a value's grade leaves to
// count, what its type says of its constructor, how a terminator leaves its
// region, and how often a region op runs its regions. Each answer is a
// choice of an enum, so no pass asks a second question to learn what the
// first one meant.
#ifndef IDR_LIB_TRANSFORMS_COUNTING_COUNTING_H
#define IDR_LIB_TRANSFORMS_COUNTING_COUNTING_H

#include "idr/IR/Families/Declaration.h"
#include "idr/IR/Families/Families.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Lifetimes.h"
#include "idr/IR/Traits.h"

#include "mlir/IR/Block.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/Value.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "mlir/Interfaces/FunctionInterfaces.h"
#include "mlir/Interfaces/ViewLikeInterface.h"
#include "llvm/Support/ErrorHandling.h"

#include <cstdint>
#include <optional>

namespace idr::counting {

// What counting does with a value, read off its grade alone:
//   - None: it holds no reference, so nothing is placed for it;
//   - Counted: freed by its count: it holds one reference of its own,
//     which exactly one use on each path consumes, and a use that only
//     reads it leaves it to be dropped after its last; one Idris lets be
//     used once has one use, so it never takes a dup;
//   - Scoped: a view its lifetime frees: it holds no reference of its own,
//     nothing drops it, and no use may consume it;
//   - Static: never freed, shared by definition: no count is ever touched,
//     and a dup or a drop of it cannot be written.
enum class Counts : std::uint8_t { None, Counted, Scoped, Static };

inline Counts countsOf(mlir::Type type) {
  Grade grade = gradeOf(type);
  if (!grade.hold)
    return Counts::None;
  switch (grade.hold->release()) {
  case Release::Counted:
    return Counts::Counted;
  case Release::Scoped:
    return Counts::Scoped;
  case Release::Static:
    return Counts::Static;
  }
  llvm_unreachable("who frees a value is one of three");
}

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

// The value a part is read from: the operand of a field read, or the source
// of a view of a buffer, the two ways a value is read in part without being
// consumed; none for any other op.
inline std::optional<mlir::Value> readFrom(mlir::Operation *def) {
  if (auto read = llvm::dyn_cast_if_present<DataFieldOp>(def))
    return read.getValue();
  if (auto view = llvm::dyn_cast_if_present<mlir::ViewLikeOpInterface>(def))
    return view.getViewSource();
  return std::nullopt;
}

// How a terminator leaves its region: out of the function (its body's
// return), out of the process (a crash, an exit, an unreachable end: no
// successor at all), or to the successors upstream's region-branch
// interfaces name (a yield, a jump), which may be regions or ops around
// it.
enum class Leaves : std::uint8_t { Frame, Process, Successors };

inline Leaves leavesOf(mlir::Operation *terminator) {
  if (llvm::isa<mlir::RegionBranchTerminatorOpInterface>(terminator))
    return Leaves::Successors;
  if (terminator->hasTrait<mlir::OpTrait::ReturnLike>() &&
      llvm::isa<mlir::FunctionOpInterface>(terminator->getParentOp()))
    return Leaves::Frame;
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

// A point between two ops of a block: right after `after`, or the block's
// start when `after` is null, so the start is the sentinel before the
// first op and no position is a case of its own.
struct Where {
  mlir::Block *block;
  mlir::Operation *after;

  static Where atStart(mlir::Block &block) { return {&block, nullptr}; }
  static Where past(mlir::Operation *op) { return {op->getBlock(), op}; }
  static Where before(mlir::Operation *op) { return {op->getBlock(), op->getPrevNode()}; }

  mlir::Block::iterator insertion() const {
    return after ? std::next(after->getIterator()) : block->begin();
  }
  bool operator==(const Where &) const = default;
};

} // namespace idr::counting

#endif // IDR_LIB_TRANSFORMS_COUNTING_COUNTING_H
