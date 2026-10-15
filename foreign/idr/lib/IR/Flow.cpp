// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The flow vocabulary's behaviour (FlowEdges.h) and the reading of it:
// forwardedValues reads what upstream's branch and region branch
// interfaces forward, flowEdgesOf joins that to what each op declares
// (lib/IR/FlowOps.cpp), so a branch's edges are said once, by upstream. The
// verifier refuses a closure or a suspension that no declaration moves.
//
// An edge carries what the value that moves carries, so a word or a world
// moves along none. A value is followed whole, or into and out of a part of
// another, which is how the label solve keeps one set per anchor and
// ownership one state per value.

#include "idr/IR/Flow.h"

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/Interfaces/ControlFlowInterfaces.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallPtrSet.h"

#include "idr/IR/IdrFlow.cpp.inc"

using namespace mlir;
using namespace idr;

//===----------------------------------------------------------------------===//
// The vocabulary
//===----------------------------------------------------------------------===//

Carriers Carriers::of(Type type) {
  Carriers carriers;
  if (isClosureType(type))
    carriers = carriers | Carrier::Closure;
  if (isLazyType(type))
    carriers = carriers | Carrier::Suspension;
  if (holdsReferences(type))
    carriers = carriers | Carrier::Reference;
  return carriers;
}

namespace {

// What `anchor` holds, where its own type says: a field's type, the
// element type, a suspension's value. A capture's is its label's
// parameter's, a memo sum's forced state its forced constructor's field,
// which only the label and the body say.
std::optional<Type> slotOf(const FlowAnchor &anchor) {
  switch (anchor.kind) {
  case FlowAnchor::Kind::Field:
    return unrestricted(cast<DataType>(anchor.type).getCtor(anchor.ctor).fields[anchor.field]);
  case FlowAnchor::Kind::Elements:
    return anchor.type;
  case FlowAnchor::Kind::Forced:
    if (auto lazy = dyn_cast<LazyType>(anchor.type))
      return unrestricted(lazy.getValue());
    return std::nullopt;
  case FlowAnchor::Kind::Capture:
    return std::nullopt;
  case FlowAnchor::Kind::Hole:
    return unrestricted(cast<DestType>(anchor.type).getValue());
  }
  llvm_unreachable("every kind of anchor is listed");
}

// The type of what is held at `point`, where the op alone says it: a use's
// or a value's, a part's slot. A parameter's or a result's is the
// function's, which the symbol user checks.
std::optional<Type> typeAt(const FlowPoint &point) {
  if (point.kind == FlowPoint::Kind::Operand || point.kind == FlowPoint::Kind::Value)
    return unrestricted(point.getValue().getType());
  if (point.kind == FlowPoint::Kind::Part)
    return slotOf(point.anchor);
  return std::nullopt;
}

// The type of what moves from `from` to `to`: the one end that says it.
std::optional<Type> movedType(const FlowPoint &from, const FlowPoint &to) {
  if (std::optional<Type> type = typeAt(from))
    return type;
  return typeAt(to);
}

} // namespace

void FlowEdges::add(Edge::Kind kind, Carriers carriers, FlowPoint from, FlowPoint to) {
  if (carriers.empty())
    return;
  Edge edge{kind, carriers, from, to, {}, {}, nullptr};
  list.push_back(edge);
}

void FlowEdges::flow(FlowPoint from, FlowPoint to, Carriers only) {
  std::optional<Type> type = movedType(from, to);
  if (type)
    add(Edge::Kind::Flow, Carriers::of(*type) & only, from, to);
}

void FlowEdges::unify(FlowPoint a, FlowPoint b) {
  std::optional<Type> type = movedType(a, b);
  if (type)
    add(Edge::Kind::Unify, Carriers::of(*type) & Carriers::labels(), a, b);
}

void FlowEdges::source(FlatSymbolRefAttr label, Value to) {
  size_t before = list.size();
  add(Edge::Kind::Source, Carriers::of(to.getType()) & Carriers::labels(), {}, FlowPoint::of(to));
  if (list.size() != before)
    list.back().label = label;
}

void FlowEdges::fresh(Value to) {
  add(Edge::Kind::Fresh, Carriers::of(to.getType()) & Carrier::Reference, {}, FlowPoint::of(to));
}

void FlowEdges::release(OpOperand &use) {
  add(Edge::Kind::Release, Carriers::of(use.get().getType()) & Carrier::Reference,
      FlowPoint::of(use), {});
}

void FlowEdges::constant(Attribute part, Value to) {
  size_t before = list.size();
  add(Edge::Kind::Constant, Carriers::of(to.getType()), {}, FlowPoint::of(to));
  if (list.size() != before)
    list.back().constant = part;
}

void FlowEdges::dispatch(CallOpInterface call) {
  // The callee runs its labels; the arguments move into whatever runs.
  Carriers carriers = Carriers::of(cast<Value>(call.getCallableForCallee()).getType()) &
                      Carriers::labels();
  if (llvm::any_of(call.getArgOperands(),
                   [](Value arg) { return Carriers::of(arg.getType()).contains(Carrier::Reference); }))
    carriers = carriers | Carrier::Reference;
  size_t before = list.size();
  add(Edge::Kind::Dispatch, carriers, {}, {});
  if (list.size() != before)
    list.back().call = call.getOperation();
}

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
// of its regions, to each of its successors.
void forwardFrom(RegionBranchOpInterface branch, RegionBranchPoint point,
                 function_ref<void(OpOperand &, Value)> each) {
  SmallVector<RegionSuccessor> successors;
  branch.getSuccessorRegions(point, successors);
  for (RegionSuccessor successor : successors)
    for (auto [use, input] : llvm::zip_equal(usesOf(branch.getSuccessorOperands(point, successor)),
                                             branch.getSuccessorInputs(successor)))
      each(use, input);
}

} // namespace

void idr::forwardedValues(Operation *op, function_ref<void(OpOperand &, Value)> each) {
  if (auto branch = dyn_cast<BranchOpInterface>(op))
    for (unsigned s = 0, n = op->getNumSuccessors(); s < n; ++s) {
      SuccessorOperands operands = branch.getSuccessorOperands(s);
      auto args = op->getSuccessor(s)->getArguments().drop_front(
          operands.getProducedOperandCount());
      for (auto [use, arg] : llvm::zip_equal(usesOf(operands.getForwardedOperands()), args))
        each(use, arg);
    }
  if (auto branch = dyn_cast<RegionBranchOpInterface>(op))
    forwardFrom(branch, RegionBranchPoint::parent(), each);
  if (auto terminator = dyn_cast<RegionBranchTerminatorOpInterface>(op))
    if (auto branch = dyn_cast_or_null<RegionBranchOpInterface>(op->getParentOp()))
      forwardFrom(branch, RegionBranchPoint(terminator), each);
}

bool idr::declaresFlow(Operation *op) {
  if (isa<FlowOpInterface, BranchOpInterface, RegionBranchOpInterface, SelectLikeOpInterface>(op))
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

// The ends each edge `op`'s model declares may name, and the one carrier
// type of an edge that carries labels.
LogicalResult verifyEdges(Operation *op, FlowOpInterface flow) {
  auto operandValue = [&](Value value) { return llvm::is_contained(op->getOperands(), value); };
  // A terminator moves into a part of what its parent makes or writes.
  auto parentValue = [&](Value value) {
    Operation *parent = op->getParentOp();
    auto result = dyn_cast<OpResult>(value);
    return (result && result.getOwner() == parent) ||
           (parent && llvm::is_contained(parent->getOperands(), value));
  };
  auto from = [&](const FlowPoint &point) {
    switch (point.kind) {
    case FlowPoint::Kind::Operand:
      return point.operand->getOwner() == op;
    case FlowPoint::Kind::Value:
      return operandValue(point.value);
    case FlowPoint::Kind::Part:
      return point.takes() ? point.operand->getOwner() == op : operandValue(point.value);
    case FlowPoint::Kind::Parameter:
    case FlowPoint::Kind::Result:
      return true;
    }
    llvm_unreachable("every kind of point is listed");
  };
  auto to = [&](const FlowPoint &point) {
    switch (point.kind) {
    case FlowPoint::Kind::Operand:
      return false;
    case FlowPoint::Kind::Value:
      return ownValue(op, point.value);
    case FlowPoint::Kind::Part:
      return !point.takes() && (ownValue(op, point.value) || operandValue(point.value) ||
                                parentValue(point.value));
    case FlowPoint::Kind::Parameter:
    case FlowPoint::Kind::Result:
      return true;
    }
    llvm_unreachable("every kind of point is listed");
  };
  auto made = [&](const FlowPoint &point) {
    return point.kind == FlowPoint::Kind::Value && ownValue(op, point.value);
  };
  FlowEdges edges;
  flow.getFlowEdges(edges);
  for (const FlowEdges::Edge &edge : edges.edges()) {
    using Kind = FlowEdges::Edge::Kind;
    bool ends = false;
    switch (edge.kind) {
    case Kind::Flow:
      ends = from(edge.from) && to(edge.to);
      break;
    case Kind::Unify:
      ends = edge.from.kind != FlowPoint::Kind::Operand && to(edge.from) && to(edge.to);
      break;
    case Kind::Source:
    case Kind::Fresh:
    case Kind::Constant:
      ends = made(edge.to);
      break;
    case Kind::Release:
      ends = edge.from.kind == FlowPoint::Kind::Operand && edge.from.operand->getOwner() == op;
      break;
    case Kind::Dispatch:
      ends = edge.call == op;
      break;
    }
    if (!ends)
      return op->emitOpError("declares a flow edge whose end is neither its own use, value or "
                             "part of one, nor a parameter or a result");
    // A reference may move between types (a natural becomes an Integer, a
    // cell a token); labels move only between places of one carrier.
    if ((edge.kind != Kind::Flow && edge.kind != Kind::Unify) ||
        !edge.carriesAny(Carriers::labels()))
      continue;
    std::optional<Type> source = typeAt(edge.from), target = typeAt(edge.to);
    if (source && target && *source != *target)
      return op->emitOpError("moves a value of carrier ")
             << *source << " into a place of carrier " << *target;
  }
  return success();
}

// One op's part of the rule.
LogicalResult verifyOp(Operation *op) {
  if (auto flow = dyn_cast<FlowOpInterface>(op))
    return verifyEdges(op, flow);
  // A first-order op moves no label, and has nothing to declare.
  bool regions = llvm::any_of(op->getRegions(), [](Region &region) {
    return llvm::any_of(region.getArguments(), holdsLabels);
  });
  if (!regions && llvm::none_of(op->getOperands(), holdsLabels) &&
      llvm::none_of(op->getResults(), holdsLabels))
    return success();
  FlowEdges edges;
  flowEdgesOf(op, edges);
  llvm::SmallPtrSet<OpOperand *, 8> moved;
  llvm::SmallPtrSet<void *, 8> read;
  for (const FlowEdges::Edge &edge : edges.edges()) {
    if (edge.from.takes())
      moved.insert(edge.from.operand);
    else if (Value value = edge.from.getValue())
      read.insert(value.getAsOpaquePointer());
  }
  for (OpOperand &use : op->getOpOperands())
    if (holdsLabels(use.get()) && !moved.contains(&use) &&
        !read.contains(use.get().getAsOpaquePointer()))
      return op->emitOpError("takes a closure or a suspension as operand #")
             << use.getOperandNumber() << ", and declares no edge for it";
  llvm::SmallPtrSet<void *, 8> inputs = successorInputs(op);
  for (const FlowEdges::Edge &edge : edges.edges())
    if (edge.to.kind == FlowPoint::Kind::Value)
      inputs.insert(edge.to.value.getAsOpaquePointer());
  for (OpResult result : op->getResults())
    if (holdsLabels(result) && !inputs.contains(result.getAsOpaquePointer()))
      return op->emitOpError("gives a closure or a suspension as result #")
             << result.getResultNumber() << ", and declares no edge for it";
  // The argument of a block a branch goes to is that branch's to declare.
  for (Region &region : op->getRegions())
    for (BlockArgument arg : region.getArguments())
      if (holdsLabels(arg) && !inputs.contains(arg.getAsOpaquePointer()))
        return op->emitOpError("binds a closure or a suspension as argument #")
               << arg.getArgNumber() << " of region #" << region.getRegionNumber()
               << ", and declares no edge for it";
  return success();
}

} // namespace

LogicalResult idr::verifyFlow(FuncOp fn) {
  // Past `higher` no closure or suspension is left, and no label moves.
  auto program = fn->getParentOfType<ProgramOp>();
  if (!program || program.getStage() != Stage::Higher)
    return success();
  WalkResult walked = fn.getBody().walk([](Operation *op) {
    return failed(verifyOp(op)) ? WalkResult::interrupt() : WalkResult::advance();
  });
  return failure(walked.wasInterrupted());
}
