// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The reading of the flow vocabulary (FlowEdges.h, whose behaviour is
// lib/IR/FlowEdges.cpp): flowEdgesOf joins what upstream's region branch
// interface forwards (forwardedValues, Flow.h) to what each op declares
// (lib/IR/FlowOps.cpp), so a region branch's edges are said once, by
// upstream. The flow interface's verifier holds each op's own edges to
// their rule, and the function verifier's one walk refuses, at each op, a
// closure or a suspension that no declaration moves.

#include "idr/IR/Flow.h"

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Match.h"

#include "mlir/Interfaces/ControlFlowInterfaces.h"

#include "llvm/ADT/BitVector.h"
#include "llvm/ADT/STLExtras.h"

#include <optional>

using namespace mlir;
using namespace idr;

//===----------------------------------------------------------------------===//
// The reading
//===----------------------------------------------------------------------===//

bool idr::declaresFlow(Operation *op) {
  if (isa<FlowOpInterface, RegionBranchOpInterface, SelectLikeOpInterface>(op))
    return true;
  return isa<RegionBranchTerminatorOpInterface>(op) &&
         isa_and_nonnull<RegionBranchOpInterface>(op->getParentOp());
}

void idr::flowEdgesOf(Operation *op, FlowEdges &edges) {
  if (auto flow = dyn_cast<FlowOpInterface>(op))
    flow.getFlowEdges(edges);
  forwardedValues(op, [&](OpOperand &use, Value input) {
    edges.flow(FlowSource::of(use), FlowPlace::of(input));
  });
  if (auto select = dyn_cast<SelectLikeOpInterface>(op)) {
    Value result = op->getResult(0);
    edges.flow(FlowSource::of(select.getTrueValue()), FlowPlace::of(result));
    edges.flow(FlowSource::of(select.getFalseValue()), FlowPlace::of(result));
  }
}

//===----------------------------------------------------------------------===//
// The rule
//===----------------------------------------------------------------------===//

namespace {

bool holdsLabels(Value value) {
  return !(Carriers::of(value.getType()) & Carriers::labels()).empty();
}

// What the edges of `op` account for of its own values, each by the number
// MLIR gives it: its operands, its results, and the arguments of its
// regions, one region's after another's. An end of another op (a yield's
// use a region branch forwards) is no value of `op` to account for.
class Covered {
public:
  explicit Covered(Operation *op)
      : op(op), operands(op->getNumOperands()), results(op->getNumResults()) {
    unsigned count = 0;
    for (Region &region : op->getRegions()) {
      firstArgument.push_back(count);
      count += region.getNumArguments();
    }
    arguments.resize(count);
  }

  // A use the op takes over.
  void take(OpOperand &use) {
    if (use.getOwner() == op)
      operands.set(use.getOperandNumber());
  }
  // A value the op reads: each of its uses that holds it.
  void read(Value value) {
    for (OpOperand &use : op->getOpOperands())
      if (use.get() == value)
        operands.set(use.getOperandNumber());
  }
  // A result of the op, or an argument of one of its regions, given whole.
  void give(Value value) {
    if (auto result = dyn_cast<OpResult>(value)) {
      if (result.getOwner() == op)
        results.set(result.getResultNumber());
      return;
    }
    auto arg = cast<BlockArgument>(value);
    Region *region = arg.getOwner()->getParent();
    if (region->getParentOp() == op && arg.getOwner() == &region->front())
      arguments.set(at(arg));
  }

  bool covers(OpOperand &use) const { return operands.test(use.getOperandNumber()); }
  bool covers(OpResult result) const { return results.test(result.getResultNumber()); }
  bool covers(BlockArgument arg) const { return arguments.test(at(arg)); }

private:
  unsigned at(BlockArgument arg) const {
    return firstArgument[arg.getOwner()->getParent()->getRegionNumber()] + arg.getArgNumber();
  }

  Operation *op;
  llvm::BitVector operands, results, arguments;
  llvm::SmallVector<unsigned, 2> firstArgument;
};

// The values of `op` a region branch makes from its predecessors: its
// results and its regions' arguments that some successor takes.
void giveSuccessorInputs(Operation *op, Covered &covered) {
  auto region = dyn_cast<RegionBranchOpInterface>(op);
  if (!region)
    return;
  auto add = [&](RegionSuccessor successor) {
    for (Value input : region.getSuccessorInputs(successor))
      covered.give(input);
  };
  add(RegionSuccessor(op));
  for (Region &body : op->getRegions())
    add(RegionSuccessor(&body));
}

// Whether `value` is a result of `op` or an argument of a block of its
// regions.
bool ownValue(Operation *op, Value value) {
  if (auto result = dyn_cast<OpResult>(value))
    return result.getOwner() == op;
  return cast<BlockArgument>(value).getOwner()->getParentOp() == op;
}

} // namespace

namespace {

// A write of a reference into memory that exists before `op` says what the
// place held: the write releases it (an Overwrite of the same value), or it
// held nothing (a Fill of it), or `op` ends the region of the exchange of
// that memory (its parent moved the contents out into the region and holds
// it as a yield target: an update, a memo cell's force), or the memory is a
// hole, written once through its linear destination. A cell's init writes
// the box it makes, and a yield of a tabulation the arrays its parent
// makes: new memory.
LogicalResult writesPartKnown(Operation *op, Value place, const FlowEdges &edges) {
  Operation *parent = op->getParentOp();
  bool terminator = op->hasTrait<OpTrait::IsTerminator>();
  Operation *maker = isa<OpResult>(place) ? cast<OpResult>(place).getOwner()
                                          : cast<BlockArgument>(place).getOwner()->getParentOp();
  if (maker == op || (terminator && maker == parent))
    return success();
  if (isa<DestType>(place.getType()))
    return success();
  auto exchange = dyn_cast_or_null<YieldTargetsOpInterface>(parent);
  if (terminator && exchange && llvm::is_contained(exchange.getYieldTargets(), place))
    return success();
  bool said = llvm::any_of(edges.edges(), [&](const FlowEdges::Edge &other) {
    return idr::match(
        other.move,
        [&](const FlowEdges::Overwrite &over) { return over.place.of == place; },
        [&](const FlowEdges::Fill &fill) { return fill.place.of == place; },
        [](const FlowEdges::Flow &) { return false; },
        [](const FlowEdges::Unify &) { return false; },
        [](const FlowEdges::Source &) { return false; },
        [](const FlowEdges::Fresh &) { return false; },
        [](const FlowEdges::Release &) { return false; },
        [](const FlowEdges::Constant &) { return false; },
        [](const FlowEdges::Dispatch &) { return false; });
  });
  if (said)
    return success();
  return op->emitOpError("writes a reference into memory that exists before it, and declares "
                         "neither what the place held (an overwrite, or a fill of a place that "
                         "held nothing) nor the exchange it ends");
}

// A move of a reference into `to`: only a move into a part writes memory,
// which the rule above asks about; a whole value, a parameter or a result
// is written by none.
LogicalResult writesKnown(Operation *op, const FlowPlace &to, const FlowEdges &edges) {
  return idr::match(
      to.at, [&](const FlowPlace::Part &part) { return writesPartKnown(op, part.of, edges); },
      [](FlowSource::Whole) { return success(); }, [](FlowSource::Parameter) { return success(); },
      [](FlowSource::Result) { return success(); });
}

} // namespace

// The ends each edge `op`'s model declares may name, the one carrier type
// of an edge that carries labels, and what a write into memory that exists
// before the op says the place held.
LogicalResult idr::verifyFlowEdges(Operation *op) {
  auto operandValue = [&](Value value) { return llvm::is_contained(op->getOperands(), value); };
  // A terminator moves into a part of what its parent makes or writes.
  auto parentValue = [&](Value value) {
    Operation *parent = op->getParentOp();
    auto result = dyn_cast<OpResult>(value);
    return (result && result.getOwner() == parent) ||
           (parent && llvm::is_contained(parent->getOperands(), value));
  };
  // A use of the op's own, which it may take.
  auto ownUse = [&](FlowSource::Taken taken) { return taken.use->getOwner() == op; };
  // A `from` names a use of the op, an operand's value or a part of either,
  // a part of one of its results or region arguments, or a parameter or a
  // result. A region reads back what an earlier step wrote into the op's
  // result (a fold's next accumulator), and the op reads out what its region
  // wrote through a place it gave the region (an answer's slot): a part of a
  // value of its own, never the whole, which as a result the op has not
  // made yet and as a region's argument is the region's.
  auto from = [&](const FlowSource &source) {
    return idr::match(
        source.at, ownUse, [&](FlowSource::Whole whole) { return operandValue(whole.value); },
        [&](const FlowSource::Part &part) {
          return idr::match(part.of, ownUse, [&](FlowSource::Whole whole) {
            return operandValue(whole.value) || ownValue(op, whole.value);
          });
        },
        [](FlowSource::Parameter) { return true; }, [](FlowSource::Result) { return true; });
  };
  // A place names a value the op makes, a part of one or of a value it or
  // its parent holds (what an overwrite writes), or a parameter or a result.
  auto toPart = [&](const FlowPlace::Part &part) {
    return ownValue(op, part.of) || operandValue(part.of) || parentValue(part.of);
  };
  auto to = [&](const FlowPlace &place) {
    return idr::match(
        place.at, [&](FlowSource::Whole whole) { return ownValue(op, whole.value); }, toPart,
        [](FlowSource::Parameter) { return true; }, [](FlowSource::Result) { return true; });
  };
  auto unnamed = [&]() -> LogicalResult {
    return op->emitOpError("declares a flow edge whose end is neither its own use, value or "
                           "part of one, nor a parameter or a result");
  };
  // A reference may move between types (a natural becomes an Integer, a
  // cell a token); labels move only between places of one carrier, which
  // a flow and a unification join.
  auto oneCarrier = [&](std::optional<Type> source, std::optional<Type> target) -> LogicalResult {
    if (source && target && *source != *target)
      return op->emitOpError("moves a value of carrier ")
             << *source << " into a place of carrier " << *target;
    return success();
  };
  FlowEdges edges;
  cast<FlowOpInterface>(op).getFlowEdges(edges);
  for (const FlowEdges::Edge &edge : edges.edges()) {
    LogicalResult rule = idr::match(
        edge.move,
        [&](const FlowEdges::Flow &move) -> LogicalResult {
          if (!from(move.from) || !to(move.to))
            return unnamed();
          if (edge.carries(Carrier::Reference) && failed(writesKnown(op, move.to, edges)))
            return failure();
          if (!edge.carriesAny(Carriers::labels()))
            return success();
          return oneCarrier(move.from.type(), move.to.type());
        },
        [&](const FlowEdges::Unify &move) -> LogicalResult {
          if (!to(move.a) || !to(move.b))
            return unnamed();
          if (!edge.carriesAny(Carriers::labels()))
            return success();
          return oneCarrier(move.a.type(), move.b.type());
        },
        [&](const FlowEdges::Source &move) -> LogicalResult {
          return ownValue(op, move.to) ? success() : unnamed();
        },
        [&](const FlowEdges::Fresh &move) -> LogicalResult {
          return ownValue(op, move.to) ? success() : unnamed();
        },
        [&](const FlowEdges::Release &move) -> LogicalResult {
          return move.use->getOwner() == op ? success() : unnamed();
        },
        [&](const FlowEdges::Overwrite &move) -> LogicalResult {
          return toPart(move.place) ? success() : unnamed();
        },
        [&](const FlowEdges::Fill &move) -> LogicalResult {
          return toPart(move.place) ? success() : unnamed();
        },
        [&](const FlowEdges::Constant &move) -> LogicalResult {
          return ownValue(op, move.to) ? success() : unnamed();
        },
        [&](FlowEdges::Dispatch move) -> LogicalResult {
          return move.call.getOperation() == op ? success() : unnamed();
        });
    if (failed(rule))
      return failure();
  }
  return success();
}

// The rule of an op that does not hold the flow interface, whose moves only
// upstream's interfaces say; an op that holds it is its interface
// verifier's.
LogicalResult idr::verifyFlowOf(Operation *op) {
  if (isa<FlowOpInterface>(op))
    return success();
  // A first-order op moves no label, and has nothing to declare.
  bool regions = llvm::any_of(op->getRegions(), [](Region &region) {
    return llvm::any_of(region.getArguments(), holdsLabels);
  });
  if (!regions && llvm::none_of(op->getOperands(), holdsLabels) &&
      llvm::none_of(op->getResults(), holdsLabels))
    return success();
  FlowEdges edges;
  flowEdgesOf(op, edges);
  // The uses the edges take, the operands whose values they read, and the
  // values they give: the uses and values each edge's `from` names, and the
  // whole values its `to` does, beside what the op makes from its
  // predecessors.
  Covered covered(op);
  giveSuccessorInputs(op, covered);
  auto take = [&](FlowSource::Taken taken) { covered.take(*taken.use); };
  auto read = [&](FlowSource::Whole whole) { covered.read(whole.value); };
  auto note = [&](const FlowSource &source) {
    idr::match(
        source.at, take, read,
        [&](const FlowSource::Part &part) { idr::match(part.of, take, read); },
        [](FlowSource::Parameter) {}, [](FlowSource::Result) {});
  };
  // A unification's first place is read as a source of it would be.
  auto notePlace = [&](const FlowPlace &place) {
    idr::match(
        place.at, read, [&](const FlowPlace::Part &part) { covered.read(part.of); },
        [](FlowSource::Parameter) {}, [](FlowSource::Result) {});
  };
  auto gives = [&](const FlowPlace &place) {
    idr::match(
        place.at, [&](FlowSource::Whole whole) { covered.give(whole.value); },
        [](const FlowPlace::Part &) {}, [](FlowSource::Parameter) {}, [](FlowSource::Result) {});
  };
  for (const FlowEdges::Edge &edge : edges.edges())
    idr::match(
        edge.move,
        [&](const FlowEdges::Flow &move) {
          note(move.from);
          gives(move.to);
        },
        [&](const FlowEdges::Unify &move) {
          notePlace(move.a);
          gives(move.b);
        },
        [&](const FlowEdges::Source &move) { covered.give(move.to); },
        [&](const FlowEdges::Fresh &move) { covered.give(move.to); },
        [&](const FlowEdges::Release &move) { covered.take(*move.use); },
        [](const FlowEdges::Overwrite &) {}, [](const FlowEdges::Fill &) {},
        [&](const FlowEdges::Constant &move) { covered.give(move.to); },
        [](const FlowEdges::Dispatch &) {});
  for (OpOperand &use : op->getOpOperands())
    if (holdsLabels(use.get()) && !covered.covers(use))
      return op->emitOpError("takes a closure or a suspension as operand #")
             << use.getOperandNumber() << ", and declares no edge for it";
  for (OpResult result : op->getResults())
    if (holdsLabels(result) && !covered.covers(result))
      return op->emitOpError("gives a closure or a suspension as result #")
             << result.getResultNumber() << ", and declares no edge for it";
  for (Region &region : op->getRegions())
    for (BlockArgument arg : region.getArguments())
      if (holdsLabels(arg) && !covered.covers(arg))
        return op->emitOpError("binds a closure or a suspension as argument #")
               << arg.getArgNumber() << " of region #" << region.getRegionNumber()
               << ", and declares no edge for it";
  return success();
}

