// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Tail position and tail position modulo a context: the one definition of
// each, the call's own check of its fact, and its function's.

#include "idr/IR/Tail.h"

#include "idr/IR/Effects/Query.h"
#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Lifetimes.h"
#include "idr/IR/Traits.h"
#include "idr/Support/Match.h"

#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <cstdint>

using namespace mlir;

namespace idr::tail {
namespace {

// The block's terminator, when the ops after `op` only change the grade of
// its results and the terminator forwards exactly those values, which
// `values` then holds; null when another op runs after `op`, so that what
// `op` gives is not yet what the block gives, or when the terminator
// forwards anything else.
Operation *passesOn(Operation *op, SmallVectorImpl<Value> &values) {
  values.assign(op->result_begin(), op->result_end());
  Operation *next = op->getNextNode();
  for (; next && !next->hasTrait<OpTrait::IsTerminator>(); next = next->getNextNode()) {
    if (!next->hasTrait<ResultCarriesOperand>())
      return nullptr;
    auto *carried = llvm::find(values, next->getOperand(0));
    if (carried == values.end())
      return nullptr;
    *carried = next->getResult(0);
  }
  return next && llvm::equal(next->getOperands(), values) ? next : nullptr;
}

// The op whose results `terminator` gives its operands to, one for one: the
// op whose region it ends, when a break may cross that op (nothing runs at
// its rejoin) and the terminator's one successor is the op's results. Null
// otherwise: for a jump into a join region, whose code goes on, for a
// terminator that never ends, and for the function's return.
Operation *rejoinOf(Operation *terminator) {
  Operation *parent = terminator->getParentOp();
  auto branch = dyn_cast<RegionBranchTerminatorOpInterface>(terminator);
  if (!branch || !parent || !parent->hasTrait<OpTrait::PropagateControlFlowBreak>())
    return nullptr;
  SmallVector<RegionSuccessor, 2> successors;
  branch.getSuccessorRegions(SmallVector<Attribute>(terminator->getNumOperands()), successors);
  if (successors.size() != 1 || successors.front().getSuccessorOp() != parent ||
      branch.getMutableSuccessorOperands(successors.front()).size() !=
          terminator->getNumOperands() ||
      parent->getNumResults() != terminator->getNumOperands())
    return nullptr;
  return parent;
}

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
  return idr::match(
      anchor.place, [](const FlowAnchor::Field &field) -> std::optional<unsigned> {
        return field.index;
      },
      [](const FlowAnchor::Capture &capture) -> std::optional<unsigned> { return capture.index; },
      [](const auto &) -> std::optional<unsigned> { return std::nullopt; });
}

// Whether `point` is the value `use` gives, taken or only read.
bool isUse(const std::variant<FlowPoint::Taken, FlowPoint::Whole> &point, OpOperand &use) {
  return idr::match(
      point, [&](FlowPoint::Taken taken) { return taken.use == &use; },
      [&](FlowPoint::Whole whole) { return whole.value == use.get(); });
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
  for (const FlowEdges::Edge &edge : edges.edges())
    idr::match(
        edge.move,
        [&](const FlowEdges::Flow &flow) {
          idr::match(
              flow.to.at,
              [&](const FlowPoint::Part &to) {
                // From the use itself into a part of a result of the op.
                bool fromUse = idr::match(
                    flow.from.at, [&](FlowPoint::Taken taken) { return taken.use == &use; },
                    [&](FlowPoint::Whole whole) { return whole.value == use.get(); },
                    [](const auto &) { return false; });
                std::optional<unsigned> field = fieldIndex(to.anchor);
                Value built = idr::match(
                    to.of, [](FlowPoint::Taken) { return Value(); },
                    [](FlowPoint::Whole whole) { return whole.value; });
                if (fromUse && field && built && built.getDefiningOp() == op)
                  moved = Moved{built, to.anchor, *field};
              },
              [&](const FlowPoint::Whole &to) {
                // From a part of the use's value to a result of the op.
                idr::match(
                    flow.from.at,
                    [&](const FlowPoint::Part &from) {
                      if (isUse(from.of, use) && to.value.getDefiningOp() == op)
                        read = Read{to.value, from.anchor};
                    },
                    [](const auto &) {});
              },
              [](const auto &) {});
        },
        [](const auto &) {});
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

Operation *tailSource(Block &block) {
  Operation *terminator = block.getTerminator();
  Operation *source = terminator->getPrevNode();
  while (source && source->hasTrait<ResultCarriesOperand>())
    source = source->getPrevNode();
  llvm::SmallVector<Value, 4> values;
  return source && passesOn(source, values) == terminator ? source : nullptr;
}

llvm::SmallVector<Block *> tailEnds(FuncOp fn) {
  llvm::SmallVector<Block *> ends;
  llvm::SmallVector<Block *, 8> spine{&fn.getBody().front()};
  while (!spine.empty()) {
    Block *block = spine.pop_back_val();
    Operation *source = tailSource(*block);
    if (!source || !source->hasTrait<OpTrait::PropagateControlFlowBreak>()) {
      ends.push_back(block);
      continue;
    }
    for (Region &region : source->getRegions())
      if (!region.empty() && rejoinOf(region.front().getTerminator()) == source)
        spine.push_back(&region.front());
  }
  return ends;
}

bool inTailPosition(Operation *op) {
  llvm::SmallVector<Value, 4> values;
  for (Operation *at = op;;) {
    Operation *terminator = passesOn(at, values);
    if (!terminator)
      return false;
    if (isa<ReturnOp>(terminator))
      return true;
    at = rejoinOf(terminator);
    if (!at)
      return false;
  }
}

std::optional<Context> contextOf(CallOp call) {
  auto fn = call->getParentOfType<FuncOp>();
  if (!fn || call.getCalleeAttr().getAttr() != fn.getSymNameAttr() || call->getNumResults() != 1 ||
      fn.getNumResults() != 1)
    return std::nullopt;
  Context context{call, {}, {}, {}};
  // The anchors before which the transformation builds the context: the
  // call, then each region op a rejoin leaves, with the steps in its block.
  llvm::SmallVector<Operation *, 2> anchors{call};

  // From the call's result to the hole: changes of grade and rejoins.
  Value at = call->getResult(0);
  for (;;) {
    OpOperand *use = onlyUse(at);
    if (!use)
      return std::nullopt;
    Operation *user = use->getOwner();
    if (user->hasTrait<ResultCarriesOperand>() && use->getOperandNumber() == 0) {
      context.approach.push_back(Regrade{user});
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
    if (user->hasTrait<ResultCarriesOperand>() && number == 0) {
      context.rest.push_back(Regrade{user});
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
              step, [&](const Regrade &regrade) { return regrade.op == op; },
              [](const Forward &) { return false; }))
        return true;
    for (const Step &step : context.rest)
      if (idr::match(
              step, [&](const Regrade &regrade) { return regrade.op == op; },
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

TailKind decide(CallOp call) {
  if (inTailPosition(call))
    return TailKind::tail;
  if (contextOf(call))
    return TailKind::modulo_context;
  return TailKind::nontail;
}

namespace {

// Whether an operand of a call that becomes a jump lives in a lifetime
// that ends with the call: its lifetime, through the views and rooms it is
// the extent of, is any but a parameter of the function, so its region
// encloses the call or it is this call's activation, and its memory would
// be gone when the callee reads it.
bool endsWithCall(Value operand, FuncOp fn) {
  Value lifetime = lifetimes::statedLifetime(operand);
  if (!lifetime)
    return false;
  auto root = dyn_cast<BlockArgument>(lifetimes::extentOf(lifetime));
  return !root || root.getOwner() != &fn.getBody().front();
}

// The lifetime rule for a call that becomes a jump.
LogicalResult verifyOperands(CallOp call, FuncOp fn) {
  for (OpOperand &operand : call->getOpOperands())
    if (endsWithCall(operand.get(), fn))
      return call.emitOpError("internal error: operand #")
             << operand.getOperandNumber()
             << " lives in a lifetime that ends with this call, which goes in its place";
  return success();
}

} // namespace

LogicalResult verify(CallOp call) {
  auto fn = call->getParentOfType<FuncOp>();
  switch (call.getTailKind()) {
  case TailKind::nontail:
    return success();
  case TailKind::tail: {
    llvm::SmallVector<Value, 4> values;
    Operation *terminator = passesOn(call, values);
    if (!terminator || (!isa<ReturnOp>(terminator) && !rejoinOf(terminator)))
      return call.emitOpError(
          "internal error: a tail call whose results its block does not give on unchanged");
    return verifyOperands(call, fn);
  }
  case TailKind::modulo_context:
    if (!contextOf(call))
      return call.emitOpError("internal error: a call modulo a context whose result goes "
                              "elsewhere than into cells built for it that its function returns");
    return verifyOperands(call, fn);
  }
  return success();
}

LogicalResult verify(FuncOp fn) {
  // The tail calls of the function, and those its spine reaches: each
  // block that ends a tail, from the body down through every region op a
  // break crosses whose results the block gives on, read once.
  unsigned tails = 0;
  fn.walk([&](CallOp call) {
    if (call.getTailKind() == TailKind::tail)
      ++tails;
  });
  if (tails == 0)
    return success();
  unsigned reached = 0;
  for (Block *end : tailEnds(fn))
    if (auto call = dyn_cast_or_null<CallOp>(tailSource(*end));
        call && call.getTailKind() == TailKind::tail)
      ++reached;
  if (reached == tails)
    return success();
  // Some tail call is off the spine: name it, reading up from each.
  LogicalResult result = success();
  fn.walk([&](CallOp call) {
    if (call.getTailKind() == TailKind::tail && !inTailPosition(call)) {
      result = call.emitOpError("internal error: a tail call that is not in tail position: an "
                                "op runs after a region op around it");
      return WalkResult::interrupt();
    }
    return WalkResult::advance();
  });
  return result;
}

} // namespace idr::tail
