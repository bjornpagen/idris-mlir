// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What the units of idr-rc-place share (lib/Transforms/Counting): one
// function's placement, its values numbered once, each with the role its
// type and its making give it (Placement.cpp, which holds the pass); the
// reverse walk over the function's regions, its stack on the heap
// (PlacementWalk.cpp); what each use and each death of a value places
// (PlacementUses.cpp); and the rewrite that follows what the walk decided
// (PlacementRewrite.cpp). The walk decides everything on the function as it
// came, so the rewrite reads only these records.
#ifndef IDR_TRANSFORMS_COUNTING_PLACEMENT_H
#define IDR_TRANSFORMS_COUNTING_PLACEMENT_H

#include "idr/Analysis/Solver/Extraction.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Id.h"
#include "idr/Transforms/Counting/Facts.h"

#include "mlir/IR/PatternMatch.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/BitVector.h"
#include "llvm/ADT/SmallBitVector.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/Twine.h"

#include <cstdint>
#include <optional>
#include <utility>
#include <variant>
#include <vector>

namespace idr::counting::placement {

struct ValueTag {
  using Minter = solver::Numbering<ValueTag>;
};

using ValueId = Id<ValueTag>;

// What placement does with a value, decided once from its type and how it
// was made:
//   - Owned: it holds one counted reference of its own;
//   - Part: a part of a counted value (a field read, a view of a buffer),
//     which holds no reference while its owner lives;
//   - Element: read out of mutable memory, so it takes a reference of its
//     own where it is read, the memory being writable while it lives;
//   - Scoped: a view its lifetime frees;
//   - Untouched: nothing to place (no reference, used once, static, or a
//     reference handed over to upstream's memory).
enum class Role : std::uint8_t { Untouched, Owned, Part, Element, Scoped };

// How a value dies at a point: after a use that only reads it (or where it
// is made, unused), or moved on by a use that consumes it.
enum class Death : std::uint8_t { Reading, Consuming };

// What lies ahead of a point on its path before the path leaves the
// function: an allocation or the caller, so a dead value must be freed; or
// only the end of the process, so nothing needs freeing.
enum class Ahead : std::uint8_t { Allocation, End };

struct State {
  llvm::BitVector live;
  Ahead ahead = Ahead::Allocation;
};

// A consuming use that takes a dup of the counted value it names, made
// right before its op.
struct DupAt {
  mlir::Operation *user;
  unsigned operand;
};

// A drop of a value at a point: of what supplied it there, when it is a part
// that took a reference of its own.
struct DropAt {
  Where where;
  ValueId value;
};

// A part that takes a reference of its own at a point, by a dup while its
// owner still lives.
struct DupSupply {
  Where where;
  ValueId part;
};

// An owner taken apart at a point, the parts it gives taking their
// references from it; its token freed and its dead fields dropped, unless
// only the end lies ahead.
struct TakeSupply {
  Where where;
  ValueId owner;
  llvm::SmallVector<ValueId, 4> parts;
  Ahead ahead;
};

// The frames of the iterative walk: a block walked backward, and a region op
// whose regions are walked last first, so a join point's targets are walked
// before the body that jumps to them.
struct BlockWalk {
  mlir::Block *block;
  mlir::Operation *next;
  State state;
  unsigned region;
};
struct OpWalk {
  mlir::Operation *op;
  Runs runs;
  State after;
  unsigned remaining;
  llvm::SmallVector<std::optional<State>, 2> entries;
  // What an op that may run its regions many times holds across them.
  llvm::BitVector held;
  // The parts live after the op that its regions may not supply.
  llvm::BitVector pinnedHere;
};
using Frame = std::variant<BlockWalk, OpWalk>;

class Placement {
public:
  explicit Placement(FuncOp fn)
      : fn(fn), numbering(fn), done(finishCopy(numbering)), count(done.count),
        roles(count, Role::Untouched), ownerOf(count, std::optional<ValueId>()),
        readFromOf(count, std::optional<ValueId>()), fieldOf(count, std::optional<unsigned>()) {}

  void run();

  unsigned dupsPlaced = 0;
  unsigned dropsPlaced = 0;
  unsigned takesPlaced = 0;
  // The most parts given a dup at one point: what a frame holds of a dead
  // owner's parts, for the frame bound's record.
  unsigned largestDupSupply = 0;
  // A promise the walk could not keep: an internal error at the op.
  mlir::LogicalResult outcome = mlir::success();

private:
  static solver::Numbering<ValueTag>::Done finishCopy(const solver::Numbering<ValueTag> &from) {
    solver::Numbering<ValueTag> copy = from;
    return std::move(copy).finish();
  }

  ValueId idOf(mlir::Value value) const { return numbering.at(value); }
  ValueId idAt(int bit) const { return count.ids()[static_cast<std::uint32_t>(bit)]; }
  mlir::Value valueOf(ValueId id) const { return done.values[id]; }

  // What each value is (Placement.cpp).
  void classify();

  // The walk (PlacementWalk.cpp).
  void stepBlock();
  void stepOp();
  void finishBlock();
  State finishOp(OpWalk &walk);
  void enterTerminator(mlir::Operation *terminator, State &state);
  llvm::SmallBitVector consumedBy(mlir::Operation *op);
  State successorState(const mlir::RegionSuccessor &successor, mlir::Operation *terminator);
  OpWalk *frameOf(mlir::Operation *op);
  bool aliveAt(ValueId owner, mlir::Operation *op, const State &state) const;
  llvm::BitVector heldBy(mlir::Operation *op) const;

  // Uses and deaths (PlacementUses.cpp).
  void operandDeaths(mlir::Operation *op, const llvm::SmallBitVector &consumed, State &state,
                     const llvm::BitVector *inside, const State *after);
  void useOperands(mlir::Operation *op, State &state, const llvm::SmallBitVector &consumed,
                   const llvm::BitVector *inside);
  void death(ValueId owner, Where where, Death kind, State &state);

  llvm::ArrayRef<std::pair<std::uint32_t, ValueId>> childrenOf(ValueId id) const {
    return llvm::ArrayRef(childRows).slice(childStart[id.index()],
                                           childStart[id.index() + 1] - childStart[id.index()]);
  }
  void fail(mlir::Operation *at, const llvm::Twine &message) {
    at->emitError("internal error: ") << message;
    outcome = mlir::failure();
  }

  // The rewrite (PlacementRewrite.cpp).
  void apply();
  mlir::Value supplied(ValueId part, mlir::Operation *at) const;
  void insertAt(mlir::RewriterBase &rewriter, const Where &where);

  FuncOp fn;
  solver::Numbering<ValueTag> numbering;
  solver::Numbering<ValueTag>::Done done;
  Count<ValueId> count;
  IndexVector<ValueId, Role> roles;
  // A part's owner (the counted value it is a part of), the value it was
  // read from, and its field, when a field read made it.
  IndexVector<ValueId, std::optional<ValueId>> ownerOf;
  IndexVector<ValueId, std::optional<ValueId>> readFromOf;
  IndexVector<ValueId, std::optional<unsigned>> fieldOf;
  // The parts read straight from each value, a row per value, each with its
  // field (none for a view of a buffer).
  std::vector<std::pair<std::uint32_t, ValueId>> childRows;
  std::vector<std::uint32_t> childStart;

  llvm::BitVector pinned;
  llvm::SmallVector<Frame, 16> stack;

  llvm::SmallVector<DupAt> dups;
  llvm::SmallVector<DropAt> drops;
  llvm::SmallVector<DupSupply> dupSupplies;
  llvm::SmallVector<TakeSupply> takeSupplies;
  llvm::SmallVector<ValueId> elementDups;
  // What each supplied part became, for the drops of it placed later.
  llvm::SmallVector<std::pair<ValueId, mlir::Value>> partValues;
  // The last op the rewrite put at each point, so a drop there follows the
  // takes and dups that read the value it frees.
  llvm::SmallVector<std::pair<Where, mlir::Operation *>> lastAt;
};

} // namespace idr::counting::placement

#endif // IDR_TRANSFORMS_COUNTING_PLACEMENT_H
