// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The flow interface: how each op that holds, takes or gives a closure or a
// suspension says where it moves, as data. The label solve and the key
// decision read these edges and nothing else, through flowEdgesOf, which
// also reads the forwarded values of upstream's branch and region branch
// interfaces, so a branch's edges are said once, by upstream. The verifier
// refuses a value of a closure or lazy carrier that no declaration moves.
//
// An edge is declared only where one end is of a closure or lazy carrier:
// a first-order value carries no label. A whole array is no such value;
// its element moves through the anchor of its element type.

#include "idr/IR/Flow.h"

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"

#include "mlir/Dialect/Tensor/IR/Tensor.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/DialectRegistry.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallPtrSet.h"

#include "idr/IR/IdrFlow.cpp.inc"

using namespace mlir;
using namespace idr;

namespace {

// The anchor of field `index` of the constructor named `ctor` of the data
// type a value of `sum` is. An op that names no constructor of a type with
// a body has no such field, and its own verifier refuses it; it declares
// no edge for it.
std::optional<FlowPoint> fieldPoint(Type sum, StringRef ctor, unsigned index) {
  DataType data = dataTypeOf(sum);
  if (!data || !data.hasBody())
    return std::nullopt;
  std::optional<unsigned> tag = data.getTag(ctor);
  if (!tag || index >= data.getCtor(*tag).fields.size())
    return std::nullopt;
  return FlowPoint::of(FlowAnchor::fieldOf(data, *tag, index));
}

// The elements of every shaped value of `shaped`'s element type.
FlowPoint elementsPoint(Type shaped) {
  Type element = cast<ShapedType>(unrestricted(shaped)).getElementType();
  return FlowPoint::of(FlowAnchor::elementsOf(element));
}

// The forced state of every cell of `lazy`'s type.
FlowPoint forcedPoint(Type lazy) { return FlowPoint::of(FlowAnchor::forcedOf(unrestricted(lazy))); }

// A keyed `use` into `to`; a keyed `value` from `from`.
void into(OpOperand &use, FlowPoint to, FlowEdges &edges) {
  if (isKeyed(use.get().getType()))
    edges.flow(FlowPoint::of(use), to);
}
void outOf(FlowPoint from, Value value, FlowEdges &edges) {
  if (isKeyed(value.getType()))
    edges.flow(from, FlowPoint::of(value));
}

//===----------------------------------------------------------------------===//
// The edges of each op
//===----------------------------------------------------------------------===//

// The model of `Op`, whose edges `edgesOf` adds.
template <typename Op, void (*edgesOf)(Op, FlowEdges &)>
struct Model : FlowOpInterface::ExternalModel<Model<Op, edgesOf>, Op> {
  void getFlowEdges(Operation *op, FlowEdges &edges) const { edgesOf(cast<Op>(op), edges); }
};

void callEdges(CallOp call, FlowEdges &edges) {
  MutableOperandRange args = call.getArgsMutable();
  for (unsigned i = 0, n = args.size(); i < n; ++i)
    into(args[i], FlowPoint::parameter(call.getCalleeAttr(), i), edges);
  for (OpResult result : call->getResults())
    outOf(FlowPoint::result(call.getCalleeAttr(), result.getResultNumber()), result, edges);
}

void returnEdges(ReturnOp ret, FlowEdges &edges) {
  auto fn = FlatSymbolRefAttr::get(ret->getParentOfType<FuncOp>().getSymNameAttr());
  for (OpOperand &use : ret->getOpOperands())
    into(use, FlowPoint::result(fn, use.getOperandNumber()), edges);
}

// A constant's parts are expanded where it is held, by the solve, which
// reads each part's carrier: a closure is a label, a constructor holds its
// fields at their anchors.
void constantEdges(ConstantOp constant, FlowEdges &edges) {
  if (isa<ClosureAttr, ConAttr>(constant.getValue()))
    edges.constant(constant.getValue(), FlowPoint::of(constant.getResult()));
}

void conEdges(ConOp con, FlowEdges &edges) {
  MutableOperandRange fields = con.getFieldsMutable();
  for (unsigned i = 0, n = fields.size(); i < n; ++i)
    if (std::optional<FlowPoint> field = fieldPoint(con.getType(), con.getCtor(), i))
      into(fields[i], *field, edges);
}

void fieldEdges(FieldOp read, FlowEdges &edges) {
  if (std::optional<FlowPoint> field = fieldPoint(
          read.getValue().getType(), read.getCtor(), static_cast<unsigned>(read.getIndex())))
    outOf(*field, read.getResult(), edges);
}

// A case's arguments are its constructor's fields; the match's results
// come from its yields, which RegionBranchOpInterface says.
void matchEdges(MatchOp match, FlowEdges &edges) {
  for (auto [r, key] : llvm::enumerate(match.getCases())) {
    Region &region = match.getCaseRegion(static_cast<unsigned>(r));
    if (region.empty())
      continue;
    for (BlockArgument arg : region.front().getArguments())
      if (std::optional<FlowPoint> field = fieldPoint(
              match.getScrutinee().getType(), cast<FlatSymbolRefAttr>(key).getValue(),
              arg.getArgNumber()))
        outOf(*field, arg, edges);
  }
}

// A closure or a suspension is its label, and its captures are the label's
// leading parameters.
template <typename Op>
void labelEdges(Op op, FlowEdges &edges) {
  edges.source(op.getCalleeAttr(), FlowPoint::of(op.getResult()));
  MutableOperandRange captures = op.getCapturesMutable();
  for (unsigned i = 0, n = captures.size(); i < n; ++i)
    into(captures[i], FlowPoint::parameter(op.getCalleeAttr(), i), edges);
}

// A suspension's label returns into the forced state of its type, the one
// slot every force of a cell of that type reads.
void suspendEdges(SuspendOp suspend, FlowEdges &edges) {
  labelEdges(suspend, edges);
  if (isKeyed(cast<LazyType>(unrestricted(suspend.getType())).getValue()))
    edges.unify(FlowPoint::result(suspend.getCalleeAttr(), 0), forcedPoint(suspend.getType()));
}

// An evaluated suspension holds its value in its forced state and runs no
// label.
void delayEdges(DelayOp delay, FlowEdges &edges) {
  into(delay.getValueMutable(), forcedPoint(delay.getType()), edges);
}

void forceEdges(ForceOp force, FlowEdges &edges) {
  if (isLazyType(force.getSuspension().getType()))
    outOf(forcedPoint(force.getSuspension().getType()), force.getResult(), edges);
}

void applyEdges(ApplyOp apply, FlowEdges &edges) { edges.dispatch(apply); }

void linEnterEdges(LinEnterOp enter, FlowEdges &edges) {
  into(enter.getValueMutable(), FlowPoint::of(enter.getResult()), edges);
}

void linUseEdges(LinUseOp use, FlowEdges &edges) {
  into(use.getLinearMutable(), FlowPoint::of(use.getResult()), edges);
}

void arrayNewEdges(ArrayNewOp made, FlowEdges &edges) {
  into(made.getFillMutable(), elementsPoint(made.getArrayType()), edges);
}

void arraySetEdges(ArraySetOp stored, FlowEdges &edges) {
  into(stored.getValueMutable(), elementsPoint(stored.getArrayType()), edges);
}

void arrayGetEdges(ArrayGetOp read, FlowEdges &edges) {
  outOf(elementsPoint(read.getArrayType()), read.getValue(), edges);
}

// Upstream's ops that move one element in or out.
void insertEdges(tensor::InsertOp insert, FlowEdges &edges) {
  into(insert.getScalarMutable(), elementsPoint(insert.getDest().getType()), edges);
}

void extractEdges(tensor::ExtractOp extract, FlowEdges &edges) {
  outOf(elementsPoint(extract.getTensor().getType()), extract.getResult(), edges);
}

void fromElementsEdges(tensor::FromElementsOp made, FlowEdges &edges) {
  for (OpOperand &use : made->getOpOperands())
    into(use, elementsPoint(made.getType()), edges);
}

void splatEdges(tensor::SplatOp splat, FlowEdges &edges) {
  into(splat.getInputMutable(), elementsPoint(splat.getType()), edges);
}

// The yield of a pad or a generate is an element of the tensor its parent
// makes.
void yieldEdges(tensor::YieldOp yield, FlowEdges &edges) {
  into(yield.getValueMutable(), elementsPoint(yield->getParentOp()->getResult(0).getType()),
       edges);
}

// A poison is no value the program computes: it holds no label.
void poisonEdges(ub::PoisonOp, FlowEdges &) {}

// Each keyed operand of `forwarded` into the successor input at its
// position.
void forward(MutableOperandRange forwarded, ValueRange inputs, FlowEdges &edges) {
  unsigned n = std::min(forwarded.size(), static_cast<unsigned>(inputs.size()));
  for (unsigned i = 0; i < n; ++i)
    if (isKeyed(forwarded[i].get().getType()))
      edges.flow(FlowPoint::of(forwarded[i]), FlowPoint::of(inputs[i]));
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

// The carrier of what is held at `point`, where the op alone says it: an
// operand, a value, an anchor. A parameter's or a result's is the symbol
// user's to check against its function.
std::optional<Type> carrier(const FlowPoint &point) {
  if (point.kind == FlowPoint::Kind::Operand)
    return unrestricted(point.operand->get().getType());
  if (point.kind == FlowPoint::Kind::Value)
    return unrestricted(point.value.getType());
  if (point.kind != FlowPoint::Kind::Anchor)
    return std::nullopt;
  const FlowAnchor &at = point.anchor;
  if (at.kind == FlowAnchor::Kind::Elements)
    return at.type;
  if (at.kind == FlowAnchor::Kind::Forced)
    return unrestricted(cast<LazyType>(at.type).getValue());
  return unrestricted(cast<DataType>(at.type).getCtor(at.ctor).fields[at.field]);
}

// Whether `value` is a result of `op` or an argument of a block of its
// regions.
bool ownValue(Operation *op, Value value) {
  if (auto result = dyn_cast<OpResult>(value))
    return result.getOwner() == op;
  return cast<BlockArgument>(value).getOwner()->getParentOp() == op;
}

// The edges `op`'s model declares: each joins two ends of one carrier,
// from an operand of its own, an anchor, a parameter or a result, to a
// result or region argument of its own, an anchor, a parameter or a result.
LogicalResult verifyEdges(Operation *op, FlowOpInterface flow) {
  // A point every op may name: one that holds for every value of a kind.
  auto shared = [](const FlowPoint &point) {
    return point.kind == FlowPoint::Kind::Anchor || point.kind == FlowPoint::Kind::Parameter ||
           point.kind == FlowPoint::Kind::Result;
  };
  auto from = [&](const FlowPoint &point) {
    return shared(point) ||
           (point.kind == FlowPoint::Kind::Operand && point.operand->getOwner() == op);
  };
  auto to = [&](const FlowPoint &point) {
    return shared(point) || (point.kind == FlowPoint::Kind::Value && ownValue(op, point.value));
  };
  FlowEdges edges;
  flow.getFlowEdges(edges);
  for (const FlowEdges::Edge &edge : edges.edges()) {
    using Kind = FlowEdges::Edge::Kind;
    bool ends = edge.kind == Kind::Flow       ? from(edge.from) && to(edge.to)
                : edge.kind == Kind::Unify    ? shared(edge.from) && shared(edge.to)
                : edge.kind == Kind::Source   ? to(edge.to)
                : edge.kind == Kind::Constant ? edge.to.kind == FlowPoint::Kind::Value &&
                                                    ownValue(op, edge.to.value)
                                              : edge.call == op;
    if (!ends)
      return op->emitOpError("declares a flow edge whose end is neither its own operand or "
                             "value nor an anchor, a parameter or a result");
    if (edge.kind != Kind::Flow && edge.kind != Kind::Unify)
      continue;
    std::optional<Type> source = carrier(edge.from), target = carrier(edge.to);
    if (source && target && *source != *target)
      return op->emitOpError("moves a value of carrier ")
             << *source << " into a place of carrier " << *target;
  }
  return success();
}

} // namespace

void idr::registerFlowInterfaceExternalModels(DialectRegistry &registry) {
  registry.addExtension(+[](MLIRContext *context, IdrDialect *) {
    CallOp::attachInterface<Model<CallOp, callEdges>>(*context);
    ReturnOp::attachInterface<Model<ReturnOp, returnEdges>>(*context);
    ConstantOp::attachInterface<Model<ConstantOp, constantEdges>>(*context);
    ConOp::attachInterface<Model<ConOp, conEdges>>(*context);
    FieldOp::attachInterface<Model<FieldOp, fieldEdges>>(*context);
    MatchOp::attachInterface<Model<MatchOp, matchEdges>>(*context);
    ClosureOp::attachInterface<Model<ClosureOp, labelEdges<ClosureOp>>>(*context);
    SuspendOp::attachInterface<Model<SuspendOp, suspendEdges>>(*context);
    DelayOp::attachInterface<Model<DelayOp, delayEdges>>(*context);
    ForceOp::attachInterface<Model<ForceOp, forceEdges>>(*context);
    ApplyOp::attachInterface<Model<ApplyOp, applyEdges>>(*context);
    LinEnterOp::attachInterface<Model<LinEnterOp, linEnterEdges>>(*context);
    LinUseOp::attachInterface<Model<LinUseOp, linUseEdges>>(*context);
    ArrayNewOp::attachInterface<Model<ArrayNewOp, arrayNewEdges>>(*context);
    ArraySetOp::attachInterface<Model<ArraySetOp, arraySetEdges>>(*context);
    ArrayGetOp::attachInterface<Model<ArrayGetOp, arrayGetEdges>>(*context);
  });
  registry.addExtension(+[](MLIRContext *context, tensor::TensorDialect *) {
    tensor::InsertOp::attachInterface<Model<tensor::InsertOp, insertEdges>>(*context);
    tensor::ExtractOp::attachInterface<Model<tensor::ExtractOp, extractEdges>>(*context);
    tensor::FromElementsOp::attachInterface<Model<tensor::FromElementsOp, fromElementsEdges>>(
        *context);
    tensor::SplatOp::attachInterface<Model<tensor::SplatOp, splatEdges>>(*context);
    tensor::YieldOp::attachInterface<Model<tensor::YieldOp, yieldEdges>>(*context);
  });
  registry.addExtension(+[](MLIRContext *context, ub::UBDialect *) {
    ub::PoisonOp::attachInterface<Model<ub::PoisonOp, poisonEdges>>(*context);
  });
}

//===----------------------------------------------------------------------===//
// The one reader, and the rule
//===----------------------------------------------------------------------===//

void idr::flowEdgesOf(Operation *op, FlowEdges &edges) {
  if (auto flow = dyn_cast<FlowOpInterface>(op))
    flow.getFlowEdges(edges);
  if (auto branch = dyn_cast<BranchOpInterface>(op))
    for (unsigned s = 0, n = op->getNumSuccessors(); s < n; ++s) {
      SuccessorOperands operands = branch.getSuccessorOperands(s);
      Block *dest = op->getSuccessor(s);
      forward(operands.getMutableForwardedOperands(),
              dest->getArguments().drop_front(operands.getProducedOperandCount()), edges);
    }
  if (auto terminator = dyn_cast<RegionBranchTerminatorOpInterface>(op))
    if (auto parent = dyn_cast<RegionBranchOpInterface>(op->getParentOp())) {
      SmallVector<RegionSuccessor> successors;
      parent.getSuccessorRegions(RegionBranchPoint(terminator), successors);
      for (RegionSuccessor successor : successors)
        forward(terminator.getMutableSuccessorOperands(successor),
                parent.getSuccessorInputs(successor), edges);
    }
  if (auto region = dyn_cast<RegionBranchOpInterface>(op)) {
    SmallVector<RegionSuccessor> successors;
    region.getSuccessorRegions(RegionBranchPoint::parent(), successors);
    for (RegionSuccessor successor : successors) {
      OperandRange entry = region.getEntrySuccessorOperands(successor);
      forward(MutableOperandRange(op, entry.getBeginOperandIndex(),
                                  static_cast<unsigned>(entry.size())),
              region.getSuccessorInputs(successor), edges);
    }
  }
}

LogicalResult idr::verifyFlow(Operation *op) {
  if (auto flow = dyn_cast<FlowOpInterface>(op))
    return verifyEdges(op, flow);
  // A first-order op moves no label, and has nothing to declare.
  auto keyed = [](Value value) { return isKeyed(value.getType()); };
  bool regions = llvm::any_of(op->getRegions(), [&](Region &region) {
    return !region.empty() && llvm::any_of(region.front().getArguments(), keyed);
  });
  if (!regions && llvm::none_of(op->getOperands(), keyed) && llvm::none_of(op->getResults(), keyed))
    return success();
  FlowEdges edges;
  flowEdgesOf(op, edges);
  llvm::SmallPtrSet<OpOperand *, 8> moved;
  for (const FlowEdges::Edge &edge : edges.edges())
    if (edge.from.kind == FlowPoint::Kind::Operand)
      moved.insert(edge.from.operand);
  for (OpOperand &use : op->getOpOperands())
    if (isKeyed(use.get().getType()) && !moved.contains(&use))
      return op->emitOpError("takes a closure or a suspension as operand #")
             << use.getOperandNumber() << ", and declares no edge for it";
  llvm::SmallPtrSet<void *, 8> inputs = successorInputs(op);
  for (OpResult result : op->getResults())
    if (isKeyed(result.getType()) && !inputs.contains(result.getAsOpaquePointer()))
      return op->emitOpError("gives a closure or a suspension as result #")
             << result.getResultNumber() << ", and declares no edge for it";
  // The argument of a block a branch goes to is that branch's to declare.
  for (Region &region : op->getRegions())
    if (!region.empty())
      for (BlockArgument arg : region.front().getArguments())
        if (isKeyed(arg.getType()) && !inputs.contains(arg.getAsOpaquePointer()))
          return op->emitOpError("binds a closure or a suspension as argument #")
                 << arg.getArgNumber() << " of region #" << region.getRegionNumber()
                 << ", and declares no edge for it";
  return success();
}
