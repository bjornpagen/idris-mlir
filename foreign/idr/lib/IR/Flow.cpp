// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The reading of the flow vocabulary (FlowEdges.h, whose behaviour is
// lib/IR/FlowEdges.cpp): forwardedValues reads what upstream's region
// branch interface forwards, flowEdgesOf joins that to what each op
// declares (lib/IR/FlowOps.cpp), so a region branch's edges are said once,
// by upstream. The flow interface's verifier holds each op's own edges to
// their rule, and the function verifier's one walk refuses, at each op, a
// closure or a suspension that no declaration moves.

#include "idr/IR/Flow.h"

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/Interfaces/ControlFlowInterfaces.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallPtrSet.h"

#include <utility>
#include <variant>

using namespace mlir;
using namespace idr;

//===----------------------------------------------------------------------===//
// The reading
//===----------------------------------------------------------------------===//

namespace {

// The uses of `operands`, as upstream's own readers of these interfaces
// take them: an empty range has no first operand to index from.
MutableArrayRef<OpOperand> usesOf(OperandRange operands) {
  return MutableArrayRef<OpOperand>(operands.getBase(), operands.size());
}

// What `branch` forwards from `point`, the op itself or a terminator of one
// of its regions, to each of its successors. A jump through `branch` to an
// enclosing join point has a successor `branch` does not own, whose inputs
// are its owner's to say.
void forwardFrom(RegionBranchOpInterface branch, RegionBranchPoint point,
                 function_ref<void(OpOperand &, Value)> each) {
  SmallVector<RegionSuccessor> successors;
  branch.getSuccessorRegions(point, successors);
  for (RegionSuccessor successor : successors)
    for (auto [use, input] :
         llvm::zip_equal(usesOf(branch.getSuccessorOperands(point, successor)),
                         getRegionBranchSuccessorOwner(successor).getSuccessorInputs(successor)))
      each(use, input);
}

} // namespace

void idr::forwardedValues(Operation *op, function_ref<void(OpOperand &, Value)> each) {
  if (auto branch = dyn_cast<RegionBranchOpInterface>(op))
    forwardFrom(branch, RegionBranchPoint::parent(), each);
  if (auto terminator = dyn_cast<RegionBranchTerminatorOpInterface>(op))
    if (auto branch = dyn_cast_or_null<RegionBranchOpInterface>(op->getParentOp()))
      forwardFrom(branch, RegionBranchPoint(terminator), each);
}

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
    edges.flow(FlowPoint::of(use), FlowPoint::of(input));
  });
  if (auto select = dyn_cast<SelectLikeOpInterface>(op)) {
    Value result = op->getResult(0);
    edges.flow(FlowPoint::of(select.getTrueValue()), FlowPoint::of(result));
    edges.flow(FlowPoint::of(select.getFalseValue()), FlowPoint::of(result));
  }
}

//===----------------------------------------------------------------------===//
// The rule
//===----------------------------------------------------------------------===//

namespace {

bool holdsLabels(Value value) {
  return !(Carriers::of(value.getType()) & Carriers::labels()).empty();
}

// The values of `op` a region branch makes from its predecessors: its
// results and its regions' arguments that some successor takes.
llvm::SmallPtrSet<void *, 8> successorInputs(Operation *op) {
  llvm::SmallPtrSet<void *, 8> inputs;
  auto region = dyn_cast<RegionBranchOpInterface>(op);
  if (!region)
    return inputs;
  auto add = [&](RegionSuccessor successor) {
    for (Value input : region.getSuccessorInputs(successor))
      inputs.insert(input.getAsOpaquePointer());
  };
  add(RegionSuccessor(op));
  for (Region &body : op->getRegions())
    add(RegionSuccessor(&body));
  return inputs;
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
// place held: the write releases it (an Overwrite of the same value), or
// `op` ends the region of the exchange of that memory (its parent moved
// the contents out into the region and holds it as a yield target: an
// update, a memo cell's force), or the memory is a hole, written once
// through its linear destination. A cell's init writes the box it makes,
// and a yield of a tabulation the arrays its parent makes: new memory.
LogicalResult writesKnown(Operation *op, const FlowEdges::Edge &edge, const FlowEdges &edges) {
  const auto *move = std::get_if<FlowEdges::Flow>(&edge.move);
  if (!move || !edge.carries(Carrier::Reference))
    return success();
  const auto *part = std::get_if<FlowPoint::Part>(&move->to.at);
  if (!part)
    return success();
  Value place = *move->to.value();
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
  bool released = llvm::any_of(edges.edges(), [&](const FlowEdges::Edge &other) {
    const auto *over = std::get_if<FlowEdges::Overwrite>(&other.move);
    return over && over->place.value() == place;
  });
  if (released)
    return success();
  return op->emitOpError("writes a reference into memory that exists before it, and declares "
                         "neither what the place held (an overwrite) nor the exchange it ends");
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
  using End = std::variant<FlowPoint::Taken, FlowPoint::Whole>;
  // A `from` names a use of the op, an operand's value or a part of either,
  // a part of one of its results, or a parameter or a result.
  auto fromEnd = [&](const End &end) {
    return std::visit(
        llvm::makeVisitor([&](FlowPoint::Taken taken) { return taken.use->getOwner() == op; },
                          [&](FlowPoint::Whole whole) { return operandValue(whole.value); }),
        end);
  };
  // A region reads back what an earlier step wrote into the op's result (a
  // fold's next accumulator): a part of a result of its own, never the
  // whole, which the op has not made yet.
  auto ownPart = [&](const End &end) {
    const auto *whole = std::get_if<FlowPoint::Whole>(&end);
    auto result = whole ? dyn_cast<OpResult>(whole->value) : OpResult();
    return result && result.getOwner() == op;
  };
  auto from = [&](const FlowPoint &point) {
    return std::visit(
        llvm::makeVisitor([&](FlowPoint::Taken taken) { return fromEnd(taken); },
                          [&](FlowPoint::Whole whole) { return fromEnd(whole); },
                          [&](const FlowPoint::Part &part) {
                            return fromEnd(part.of) || ownPart(part.of);
                          },
                          [](FlowPoint::Parameter) { return true; },
                          [](FlowPoint::Result) { return true; }),
        point.at);
  };
  // A `to` names a value the op makes, a part of one or of a value it or its
  // parent holds, or a parameter or a result; never a use it takes.
  auto to = [&](const FlowPoint &point) {
    auto partOf = [&](const End &end) {
      return std::visit(llvm::makeVisitor([](FlowPoint::Taken) { return false; },
                                          [&](FlowPoint::Whole whole) {
                                            return ownValue(op, whole.value) ||
                                                   operandValue(whole.value) ||
                                                   parentValue(whole.value);
                                          }),
                        end);
    };
    return std::visit(
        llvm::makeVisitor([](FlowPoint::Taken) { return false; },
                          [&](FlowPoint::Whole whole) { return ownValue(op, whole.value); },
                          [&](const FlowPoint::Part &part) { return partOf(part.of); },
                          [](FlowPoint::Parameter) { return true; },
                          [](FlowPoint::Result) { return true; }),
        point.at);
  };
  using Ends = std::pair<const FlowPoint *, const FlowPoint *>;
  FlowEdges edges;
  cast<FlowOpInterface>(op).getFlowEdges(edges);
  for (const FlowEdges::Edge &edge : edges.edges()) {
    bool named = std::visit(
        llvm::makeVisitor(
            [&](const FlowEdges::Flow &move) { return from(move.from) && to(move.to); },
            [&](const FlowEdges::Unify &move) { return to(move.a) && to(move.b); },
            [&](const FlowEdges::Source &move) { return ownValue(op, move.to); },
            [&](const FlowEdges::Fresh &move) { return ownValue(op, move.to); },
            [&](const FlowEdges::Release &move) { return move.use->getOwner() == op; },
            [&](const FlowEdges::Overwrite &move) {
              return std::holds_alternative<FlowPoint::Part>(move.place.at) && to(move.place);
            },
            [&](const FlowEdges::Constant &move) { return ownValue(op, move.to); },
            [&](FlowEdges::Dispatch move) { return move.call.getOperation() == op; }),
        edge.move);
    if (!named)
      return op->emitOpError("declares a flow edge whose end is neither its own use, value or "
                             "part of one, nor a parameter or a result");
    // A reference may move between types (a natural becomes an Integer, a
    // cell a token); labels move only between places of one carrier, which
    // a flow and a unification join.
    std::optional<Ends> places = std::visit(
        llvm::makeVisitor(
            [](const FlowEdges::Flow &move) -> std::optional<Ends> {
              return Ends{&move.from, &move.to};
            },
            [](const FlowEdges::Unify &move) -> std::optional<Ends> {
              return Ends{&move.a, &move.b};
            },
            [](const FlowEdges::Source &) -> std::optional<Ends> { return std::nullopt; },
            [](const FlowEdges::Fresh &) -> std::optional<Ends> { return std::nullopt; },
            [](const FlowEdges::Release &) -> std::optional<Ends> { return std::nullopt; },
            [](const FlowEdges::Overwrite &) -> std::optional<Ends> { return std::nullopt; },
            [](const FlowEdges::Constant &) -> std::optional<Ends> { return std::nullopt; },
            [](const FlowEdges::Dispatch &) -> std::optional<Ends> { return std::nullopt; }),
        edge.move);
    if (failed(writesKnown(op, edge, edges)))
      return failure();
    if (!places || !edge.carriesAny(Carriers::labels()))
      continue;
    std::optional<Type> source = places->first->type(), target = places->second->type();
    if (source && target && *source != *target)
      return op->emitOpError("moves a value of carrier ")
             << *source << " into a place of carrier " << *target;
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
  // The uses the edges take, the values they read, and the values they give:
  // the uses and values each edge's `from` names, and the whole values its
  // `to` does.
  llvm::SmallPtrSet<OpOperand *, 8> moved;
  llvm::SmallPtrSet<void *, 8> read;
  llvm::SmallPtrSet<void *, 8> inputs = successorInputs(op);
  auto note = [&](const FlowPoint &point) {
    if (std::optional<OpOperand *> use = point.taken())
      moved.insert(*use);
    else if (std::optional<Value> value = point.value())
      read.insert(value->getAsOpaquePointer());
  };
  auto give = [&](Value value) { inputs.insert(value.getAsOpaquePointer()); };
  auto gives = [&](const FlowPoint &point) {
    if (const auto *whole = std::get_if<FlowPoint::Whole>(&point.at))
      give(whole->value);
  };
  for (const FlowEdges::Edge &edge : edges.edges())
    std::visit(llvm::makeVisitor(
                   [&](const FlowEdges::Flow &move) {
                     note(move.from);
                     gives(move.to);
                   },
                   [&](const FlowEdges::Unify &move) {
                     note(move.a);
                     gives(move.b);
                   },
                   [&](const FlowEdges::Source &move) { give(move.to); },
                   [&](const FlowEdges::Fresh &move) { give(move.to); },
                   [&](const FlowEdges::Release &move) { moved.insert(move.use); },
                   [](const FlowEdges::Overwrite &) {},
                   [&](const FlowEdges::Constant &move) { give(move.to); },
                   [](const FlowEdges::Dispatch &) {}),
               edge.move);
  for (OpOperand &use : op->getOpOperands())
    if (holdsLabels(use.get()) && !moved.contains(&use) &&
        !read.contains(use.get().getAsOpaquePointer()))
      return op->emitOpError("takes a closure or a suspension as operand #")
             << use.getOperandNumber() << ", and declares no edge for it";
  for (OpResult result : op->getResults())
    if (holdsLabels(result) && !inputs.contains(result.getAsOpaquePointer()))
      return op->emitOpError("gives a closure or a suspension as result #")
             << result.getResultNumber() << ", and declares no edge for it";
  for (Region &region : op->getRegions())
    for (BlockArgument arg : region.getArguments())
      if (holdsLabels(arg) && !inputs.contains(arg.getAsOpaquePointer()))
        return op->emitOpError("binds a closure or a suspension as argument #")
               << arg.getArgNumber() << " of region #" << region.getRegionNumber()
               << ", and declares no edge for it";
  return success();
}

