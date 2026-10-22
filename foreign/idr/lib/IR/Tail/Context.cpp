// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Tail position modulo a context: the one definition of the rule that
// admits a self call whose result goes only into cells built for it, which
// its function returns. Read off the flow each op declares, so no op is
// named here.

#include "idr/IR/Tail.h"

#include "idr/IR/Effects/Whole.h"
#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Match.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <cstdint>

using namespace mlir;

namespace idr::tail {
namespace {

// The one use of `value`, if it has exactly one.
OpOperand *onlyUse(Value value) {
  return value.hasOneUse() ? &*value.getUses().begin() : nullptr;
}

// Where a flow edge of an op moves the value a use gives: into field
// `field` of `built`, a value the op makes for it; or, read back, out of
// the part `anchor` of the use's value as `part`.
struct Moved {
  Value built;
  FlowAnchor anchor;
  unsigned field;
};
struct Read {
  Value part;
  FlowAnchor anchor;
};

// The field index an anchor names, where it names a field of a
// constructor or a capture of a closure: the places a hole or a context's
// part may be.
std::optional<unsigned> fieldIndex(const FlowAnchor &anchor) {
  using Found = std::optional<unsigned>;
  return idr::match(
      anchor.place, [](const FlowAnchor::Field &field) -> Found { return field.index; },
      [](const FlowAnchor::Capture &capture) -> Found { return capture.index; },
      [](const FlowAnchor::Elements &) -> Found { return std::nullopt; },
      [](const FlowAnchor::Forced &) -> Found { return std::nullopt; },
      [](const FlowAnchor::MemoState &) -> Found { return std::nullopt; },
      [](const FlowAnchor::Hole &) -> Found { return std::nullopt; });
}

// Whether `source` is the value `use` gives, taken or only read.
bool isUse(const std::variant<FlowSource::Taken, FlowSource::Whole> &source, OpOperand &use) {
  return idr::match(
      source, [&](FlowSource::Taken taken) { return taken.use == &use; },
      [&](FlowSource::Whole whole) { return whole.value == use.get(); });
}

// What the op that holds `use` declares it does with the use's value: a
// move into a part of a value it builds (one of its results, never memory
// that was there before it), or a read of a part back. The flow interface
// says it, for a cell's initialization, a constructor laid out inline and
// a closure alike, so no op is named here. That nothing else holds what it
// builds is the path's: each value on it has the next step as its one use.
std::variant<std::monostate, Moved, Read> movesOf(OpOperand &use) {
  Operation *op = use.getOwner();
  FlowEdges edges;
  flowEdgesOf(op, edges);
  std::optional<Moved> moved;
  std::optional<Read> read;
  // Only a flow moves a value; every other edge says nothing of where.
  auto readFlow = [&](const FlowEdges::Flow &flow) {
    idr::match(
        flow.to.at,
        [&](const FlowPlace::Part &to) {
          // From the use itself into a part of a result of the op.
          bool fromUse = idr::match(
              flow.from.at, [&](FlowSource::Taken taken) { return taken.use == &use; },
              [&](FlowSource::Whole whole) { return whole.value == use.get(); },
              [](const FlowSource::Part &) { return false; },
              [](FlowSource::Parameter) { return false; }, [](FlowSource::Result) { return false; });
          std::optional<unsigned> field = fieldIndex(to.anchor);
          if (fromUse && field && to.of.getDefiningOp() == op)
            moved = Moved{to.of, to.anchor, *field};
        },
        [&](FlowSource::Whole to) {
          // From a part of the use's value to a result of the op.
          idr::match(
              flow.from.at,
              [&](const FlowSource::Part &from) {
                if (isUse(from.of, use) && to.value.getDefiningOp() == op)
                  read = Read{to.value, from.anchor};
              },
              [](FlowSource::Taken) {}, [](FlowSource::Whole) {}, [](FlowSource::Parameter) {},
              [](FlowSource::Result) {});
        },
        [](FlowSource::Parameter) {}, [](FlowSource::Result) {});
  };
  for (const FlowEdges::Edge &edge : edges.edges())
    idr::match(edge.move, readFlow, [](const FlowEdges::Unify &) {},
               [](const FlowEdges::Source &) {}, [](const FlowEdges::Fresh &) {},
               [](const FlowEdges::Release &) {}, [](const FlowEdges::Overwrite &) {},
               [](const FlowEdges::Fill &) {}, [](const FlowEdges::Constant &) {},
               [](const FlowEdges::Dispatch &) {});
  if (moved)
    return *moved;
  if (read)
    return *read;
  return std::monostate{};
}

// Whether `value` is defined before `anchor`, an op of `block`, so that an
// op moved before `anchor` may read it: in a block around `block`, or in
// `block` before `anchor`, or by an op moved before it too.
bool availableBefore(Value value, Operation *anchor, llvm::ArrayRef<Operation *> moved) {
  // A block's arguments, this block's or one around it, come before all of
  // its ops.
  Operation *def = value.getDefiningOp();
  if (!def || def->getBlock() != anchor->getBlock())
    return true;
  return def->isBeforeInBlock(anchor) || llvm::is_contained(moved, def);
}

// The ops of `anchor`'s block after it, its terminator aside: what a
// context built before `anchor` moves there.
llvm::SmallVector<Operation *> opsAfter(Operation *anchor) {
  llvm::SmallVector<Operation *> after;
  for (Operation *op = anchor->getNextNode(); op && !op->hasTrait<OpTrait::IsTerminator>();
       op = op->getNextNode())
    after.push_back(op);
  return after;
}

// Whether the ops after `anchor` in its block may run before it, the path's
// ops building on the hole and every other op on values defined before
// `anchor`: a move the context's construction makes. `onPath` names the
// path's ops, whose operand on the path is the hole's value then. Every op
// moved crosses `anchor` with everything in it (the call, or a region op
// holding it), so neither may tell: a crash, a loop or an IO action of the
// call's runs after what came after it, and nothing it writes is read
// before.
template <typename OnPath>
bool movableBefore(Operation *anchor, OnPath onPath) {
  llvm::SmallVector<Operation *> after = opsAfter(anchor);
  for (Operation *op : after) {
    bool path = onPath(op);
    if (!effects::mayMoveAcross(op, anchor))
      return false;
    for (OpOperand &operand : op->getOpOperands()) {
      Operation *def = operand.get().getDefiningOp();
      // The path's own value, which the hole stands for once moved.
      if (path && (def == anchor || (def && onPath(def))))
        continue;
      if (!availableBefore(operand.get(), anchor, after))
        return false;
    }
  }
  return true;
}

} // namespace

std::optional<Context> contextOf(CallOp call) {
  auto fn = call->getParentOfType<FuncOp>();
  if (!fn || call.getCalleeAttr().getAttr() != fn.getSymNameAttr() || call->getNumResults() != 1 ||
      fn.getNumResults() != 1)
    return std::nullopt;
  Context context{call, {}, {}, {}};
  // The anchors before which the transformation builds the context: the
  // call, then each region op a rejoin leaves, with the steps in its block.
  llvm::SmallVector<Operation *, 2> anchors{call};

  // From the call's result to the hole: carries and rejoins.
  Value at = call->getResult(0);
  for (;;) {
    OpOperand *use = onlyUse(at);
    if (!use)
      return std::nullopt;
    Operation *user = use->getOwner();
    if (carriesOn(user) && use->getOperandNumber() == 0) {
      context.approach.push_back(Carry{user});
      at = user->getResult(0);
      continue;
    }
    if (user->hasTrait<OpTrait::IsTerminator>()) {
      Operation *rejoin = rejoinOf(user);
      if (!rejoin)
        return std::nullopt;
      unsigned position = use->getOperandNumber();
      context.approach.push_back(Forward{user, position});
      anchors.push_back(rejoin);
      at = rejoin->getResult(position);
      continue;
    }
    // The hole is a field of a cell in memory that outlives the call: a
    // cell of a lexical lifetime ends with the function.
    std::optional<Into> hole = idr::match(
        movesOf(*use), [](std::monostate) -> std::optional<Into> { return std::nullopt; },
        [](const Read &) -> std::optional<Into> { return std::nullopt; },
        [&](const Moved &moved) -> std::optional<Into> {
          if (!isCellPointer(moved.built.getType()) ||
              freedBy(moved.built.getType(), Release::Scoped))
            return std::nullopt;
          return Into{user, use->getOperandNumber(), moved.field, moved.built};
        });
    if (!hole)
      return std::nullopt;
    context.hole = *hole;
    at = hole->built;
    break;
  }

  // From the hole's cell to the return. `parts` is where the cell is
  // inside `at`, outermost first: empty while `at` is the cell itself.
  llvm::SmallVector<FlowAnchor, 4> parts;
  // Whether the path has just come out of a rejoin: the next cell it moves
  // into is a hole too, which each region of the rejoin fills, so it is a
  // cell in memory that outlives the call, as the first is.
  enum class After : std::uint8_t { Step, Rejoin };
  After after = After::Step;
  for (;;) {
    // A value laid out inline may have its other parts read, which takes
    // nothing of the hole; a cell in memory is read by nothing.
    bool inMemory = isCellPointer(at.getType());
    // The one use that takes the hole on, the step it makes and the value
    // after it; the return ends the path.
    OpOperand *onward = nullptr;
    for (OpOperand &use : at.getUses()) {
      Operation *user = use.getOwner();
      bool otherPart = !inMemory && !user->hasTrait<OpTrait::IsTerminator>() &&
                       idr::match(
                           movesOf(use), [](std::monostate) { return false; },
                           [](const Moved &) { return false; },
                           [&](const Read &read) {
                             return parts.empty() || !(read.anchor == parts.front());
                           });
      if (otherPart)
        continue;
      if (onward)
        return std::nullopt;
      onward = &use;
    }
    if (!onward)
      return std::nullopt;
    Operation *user = onward->getOwner();
    unsigned number = onward->getOperandNumber();
    if (isa<ReturnOp>(user)) {
      // The function gives the value that holds the hole.
      if (user->getNumOperands() != 1)
        return std::nullopt;
      break;
    }
    if (carriesOn(user) && number == 0) {
      context.rest.push_back(Carry{user});
      at = user->getResult(0);
      continue;
    }
    if (user->hasTrait<OpTrait::IsTerminator>()) {
      Operation *rejoin = rejoinOf(user);
      if (!rejoin)
        return std::nullopt;
      context.rest.push_back(Forward{user, number});
      anchors.push_back(rejoin);
      at = rejoin->getResult(number);
      after = After::Rejoin;
      continue;
    }
    bool outOfRejoin = after == After::Rejoin;
    after = After::Step;
    std::optional<Value> next = idr::match(
        movesOf(*onward), [](std::monostate) -> std::optional<Value> { return std::nullopt; },
        [&](const Moved &moved) -> std::optional<Value> {
          if (outOfRejoin && (!isCellPointer(moved.built.getType()) ||
                              freedBy(moved.built.getType(), Release::Scoped)))
            return std::nullopt;
          context.rest.push_back(Into{user, number, moved.field, moved.built});
          parts.insert(parts.begin(), moved.anchor);
          return moved.built;
        },
        [&](const Read &read) -> std::optional<Value> {
          if (outOfRejoin)
            return std::nullopt;
          context.rest.push_back(ReadBack{user, read.part});
          parts.erase(parts.begin());
          return read.part;
        });
    if (!next)
      return std::nullopt;
    at = *next;
  }

  // Every op the transformation builds before the call, or before a region
  // op the path leaves, may run there.
  auto onPath = [&](Operation *op) {
    if (op == context.hole.op)
      return true;
    for (const Approach &step : context.approach)
      if (idr::match(
              step, [&](const Carry &carry) { return carry.op == op; },
              [](const Forward &) { return false; }))
        return true;
    for (const Step &step : context.rest)
      if (idr::match(
              step, [&](const Carry &carry) { return carry.op == op; },
              [&](const Into &into) { return into.op == op; },
              [&](const ReadBack &read) { return read.op == op; },
              [](const Forward &) { return false; }))
        return true;
    return false;
  };
  for (Operation *anchor : anchors)
    if (!movableBefore(anchor, onPath))
      return std::nullopt;
  return context;
}

} // namespace idr::tail
