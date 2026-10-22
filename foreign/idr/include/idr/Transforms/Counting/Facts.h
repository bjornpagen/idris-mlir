// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What counting's passes share (lib/Transforms/Counting), read once from
// the types, the moves ops declare and upstream's control-flow interfaces:
// what a value's grade leaves to count, what its type says of its
// constructor, which values are elements read out of memory and left
// there, how a terminator leaves its region, and how often a region op runs
// its regions. Each answer is a choice of an enum, so no pass asks a second
// question to learn what the first one meant.
#ifndef IDR_TRANSFORMS_COUNTING_FACTS_H
#define IDR_TRANSFORMS_COUNTING_FACTS_H

#include "idr/IR/Families/Declaration.h"
#include "idr/IR/Families/Families.h"
#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Lifetimes.h"
#include "idr/IR/Traits.h"
#include "idr/Support/Match.h"

#include "mlir/IR/Block.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/Value.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "mlir/Interfaces/FunctionInterfaces.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/Support/ErrorHandling.h"

#include <cstdint>
#include <iterator>
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

// The buffer `value` is read out of as an element and left in, as the op
// that reads it declares its moves: the element moves whole out of the
// elements of memory the op only reads, and the op neither empties that
// place (an overwrite: a take moves the element out with its reference)
// nor makes the value fresh (a copy gives it a reference of its own). A
// load and an array's read, upstream's and ours alike. None for any other
// value. The slot keeps its reference while nothing overwrites it, so the
// element holds one of its own only where counting gives it one.
inline std::optional<mlir::Value> elementBufferOf(mlir::Value value) {
  mlir::Operation *op = value.getDefiningOp();
  if (!op || !holdsReferences(value.getType()))
    return std::nullopt;
  FlowEdges edges;
  flowEdgesOf(op, edges);
  std::optional<mlir::Value> buffer;
  enum class Given : std::uint8_t { Borrowed, OwnReference } given = Given::Borrowed;
  // The memory a move out of a part of a value the op only reads comes
  // from, where the part is the elements of a buffer.
  auto elementsRead = [](const FlowSource::Part &part) -> std::optional<mlir::Value> {
    bool elements = match(
        part.anchor.place, [](const FlowAnchor::Elements &) { return true; },
        [](const OneOf<FlowAnchor::Field, FlowAnchor::Forced, FlowAnchor::MemoState,
                       FlowAnchor::Capture, FlowAnchor::Hole> auto &) { return false; });
    return match(
        part.of, [](const FlowSource::Taken &) -> std::optional<mlir::Value> { return std::nullopt; },
        [&](const FlowSource::Whole &read) -> std::optional<mlir::Value> {
          if (!elements || !llvm::isa<mlir::BaseMemRefType>(unrestricted(read.value.getType())))
            return std::nullopt;
          return read.value;
        });
  };
  for (const FlowEdges::Edge &edge : edges.edges())
    match(
        edge.move,
        [&](const FlowEdges::Flow &flow) {
          bool intoValue = match(
              flow.to.at, [&](const FlowSource::Whole &to) { return to.value == value; },
              [](const OneOf<FlowPlace::Part, FlowSource::Parameter, FlowSource::Result> auto &) {
                return false;
              });
          std::optional<mlir::Value> from = match(
              flow.from.at, elementsRead,
              [](const OneOf<FlowSource::Taken, FlowSource::Whole, FlowSource::Parameter,
                             FlowSource::Result> auto &) -> std::optional<mlir::Value> {
                return std::nullopt;
              });
          if (intoValue && from)
            buffer = from;
        },
        [&](const FlowEdges::Fresh &fresh) {
          if (fresh.to == value)
            given = Given::OwnReference;
        },
        [&](const FlowEdges::Overwrite &) { given = Given::OwnReference; },
        [](const OneOf<FlowEdges::Unify, FlowEdges::Source, FlowEdges::Release, FlowEdges::Constant,
                       FlowEdges::Dispatch> auto &) {});
  if (given == Given::OwnReference)
    return std::nullopt;
  return buffer;
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
