// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The edges of each op of ours that holds the flow interface, and of the
// upstream ops that move a value into or out of the elements of a tensor
// or a buffer or make one from nothing, which hold it as an external model:
// where what each holds, takes or gives moves, as data (FlowEdges.h). A
// value is followed whole, or into and out of a part of another (a field,
// the elements, the forced state, a capture, a hole). And ub.unreachable's
// effects, none, which upstream leaves undeclared.

#include "idr/IR/Flow.h"

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"

#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Dialect/Tensor/IR/Tensor.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/DialectRegistry.h"

#include "llvm/ADT/STLExtras.h"

using namespace mlir;
using namespace idr;

//===----------------------------------------------------------------------===//
// The edges of each op
//===----------------------------------------------------------------------===//

namespace {

FlowAnchor elementsOf(Type shaped) {
  return FlowAnchor::elementsOf(cast<ShapedType>(unrestricted(shaped)).getElementType());
}

// The forced state of a suspension of `lazy`, at any grade: the one place a
// lazy value's type is read as one, which every operand that holds a
// suspension is by its constraint.
FlowAnchor forcedOf(Type lazy) {
  return FlowAnchor::forcedOf(cast<LazyType>(unrestricted(lazy)));
}

// A constructor built into `value`, its constructor `tag` of `data`: each
// field given (`fields`, the fields that are not `holes`, in order) moves
// into its field of the value, which takes it over.
void builtEdges(Value value, DataType data, Tag tag, MutableOperandRange fields,
                ArrayRef<int32_t> holes, FlowEdges &edges) {
  unsigned given = 0;
  for (unsigned i = 0, n = static_cast<unsigned>(data.getCtor(tag).fields.size()); i < n; ++i) {
    if (llvm::is_contained(holes, static_cast<int32_t>(i)))
      continue;
    edges.flow(FlowPoint::of(fields[given++]),
               FlowPoint::partOf(value, FlowAnchor::fieldOf(data, tag, i)));
  }
}

// A closure or a suspension is its label, a new cell that takes its
// captures over. A capture's labels go to the label's parameter, where the
// label's body reads them every time it runs; its reference goes into the
// cell, which holds it until the cell is freed.
template <typename Op>
void labelEdges(Op op, FlowEdges &edges) {
  FlatSymbolRefAttr label = op.getCalleeAttr();
  Value self = op.getResult();
  Type carrier = unrestricted(self.getType());
  edges.source(label, self);
  MutableOperandRange captures = op.getCapturesMutable();
  for (unsigned i = 0, n = captures.size(); i < n; ++i) {
    edges.flow(FlowPoint::of(captures[i]), FlowPoint::parameter(label, i), Carriers::labels());
    edges.flow(FlowPoint::of(captures[i]),
               FlowPoint::partOf(self, FlowAnchor::captureOf(carrier, i)), Carrier::Reference);
  }
  edges.fresh(self);
}

// An op that hands its operand to its result: the result is the operand's
// value, and the op takes it over.
void handOn(OpOperand &use, Value result, FlowEdges &edges) {
  edges.flow(FlowPoint::of(use), FlowPoint::of(result));
}

} // namespace

// A call moves its arguments into its callee's parameters, which take them
// over where they are owned; its results are its callee's.
void idr::CallOp::getFlowEdges(FlowEdges &edges) {
  FlatSymbolRefAttr callee = getCalleeAttr();
  MutableOperandRange args = getArgsMutable();
  for (unsigned i = 0, n = args.size(); i < n; ++i)
    edges.flow(FlowPoint::of(args[i]), FlowPoint::parameter(callee, i));
  for (OpResult result : getOperation()->getResults())
    edges.flow(FlowPoint::result(callee, result.getResultNumber()), FlowPoint::of(Value(result)));
}

void idr::ReturnOp::getFlowEdges(FlowEdges &edges) {
  auto fn = FlatSymbolRefAttr::get(cast<FuncOp>(getOperation()->getParentOp()).getSymNameAttr());
  for (OpOperand &use : getOperation()->getOpOperands())
    edges.flow(FlowPoint::of(use), FlowPoint::result(fn, use.getOperandNumber()));
}

// A constant's parts are expanded where it is held, by the reader that
// follows them: a closure is a label, a constructor holds its fields at
// their anchors, and static data is every copy's.
void idr::ConstantOp::getFlowEdges(FlowEdges &edges) { edges.constant(getValue(), getResult()); }

// A constructor value is new, built of the fields given; it has no hole,
// which only a cell has.
void idr::ConOp::getFlowEdges(FlowEdges &edges) {
  Value value = getResult();
  builtEdges(value, getDataType(), getTag(), getFieldsMutable(), {}, edges);
  edges.fresh(value);
}

// A read of a field gives what the field holds; the value is only read.
void idr::FieldOp::getFlowEdges(FlowEdges &edges) {
  FlowAnchor field =
      FlowAnchor::fieldOf(getDataType(), getTag(), static_cast<unsigned>(getIndex()));
  edges.flow(FlowPoint::partOf(getValue(), field), FlowPoint::of(getResult()));
}

// The tag is read, and nothing moves.
void idr::TagOp::getFlowEdges(FlowEdges &) {}

// The value moves into the hole the destination writes.
void idr::DestWriteOp::getFlowEdges(FlowEdges &edges) {
  TypedValue<DestType> dest = getDest();
  edges.flow(FlowPoint::of(getValueMutable()),
             FlowPoint::partOf(dest, FlowAnchor::holeOf(dest.getType())));
}

void idr::ClosureOp::getFlowEdges(FlowEdges &edges) { labelEdges(*this, edges); }

// A suspension's label returns into the forced state of its type, the one
// slot every force of a cell of that type reads.
void idr::SuspendOp::getFlowEdges(FlowEdges &edges) {
  labelEdges(*this, edges);
  edges.unify(FlowPoint::result(getCalleeAttr(), 0),
              FlowPoint::partOf(getResult(), forcedOf(getType())));
}

// An evaluated suspension holds its value in its forced state and runs no
// label.
void idr::DelayOp::getFlowEdges(FlowEdges &edges) {
  edges.flow(FlowPoint::of(getValueMutable()), FlowPoint::partOf(getResult(), forcedOf(getType())));
  edges.fresh(getResult());
}

// A force reads the forced state of its cell.
void idr::ForceOp::getFlowEdges(FlowEdges &edges) {
  Value cell = getSuspension();
  edges.flow(FlowPoint::partOf(cell, forcedOf(cell.getType())), FlowPoint::of(getResult()));
}

void idr::ApplyOp::getFlowEdges(FlowEdges &edges) { edges.dispatch(*this); }

// A guard that passes its operand on takes it over and gives it.
void idr::CheckNonzeroOp::getFlowEdges(FlowEdges &edges) {
  handOn(getOperation()->getOpOperand(0), getOperation()->getResult(0), edges);
}

void idr::CheckNonemptyOp::getFlowEdges(FlowEdges &edges) {
  handOn(getOperation()->getOpOperand(0), getOperation()->getResult(0), edges);
}

// A natural is its Integer at another type: the reference goes on.
void idr::NatToBigOp::getFlowEdges(FlowEdges &edges) {
  handOn(getOperation()->getOpOperand(0), getOperation()->getResult(0), edges);
}

void idr::LinEnterOp::getFlowEdges(FlowEdges &edges) {
  handOn(getValueMutable(), getResult(), edges);
}

void idr::LinUseOp::getFlowEdges(FlowEdges &edges) {
  handOn(getLinearMutable(), getResult(), edges);
}

// A reference of its own to the value it reads, which keeps its own.
void idr::DupOp::getFlowEdges(FlowEdges &edges) {
  edges.flow(FlowPoint::of(getValue()), FlowPoint::of(getResult()));
}

void idr::DropOp::getFlowEdges(FlowEdges &edges) { edges.release(getValueMutable()); }

// A view: the value read, which keeps its reference.
void idr::BorrowOp::getFlowEdges(FlowEdges &edges) {
  edges.flow(FlowPoint::of(getValue()), FlowPoint::of(getResult()));
}

// The reference is given up here, and the result is a value no flow
// explains: what the operand alone reached is forgotten.
void idr::ShareOp::getFlowEdges(FlowEdges &edges) { edges.release(getValueMutable()); }

// A new heap cell: no other value holds a reference to it.
void idr::CellNewOp::getFlowEdges(FlowEdges &edges) { edges.fresh(getCell()); }

// A cell in the frame is the frame's, lent to whatever holds it: it is new
// to no one, so nothing is declared, and its box is not fresh.
void idr::CellStackOp::getFlowEdges(FlowEdges &) {}

// The token's cell is given up here, and the cell made of it, or a new one
// for a token of no cell, is new.
void idr::CellRecycleOp::getFlowEdges(FlowEdges &edges) {
  edges.release(getTokenMutable());
  edges.fresh(getCell());
}

// The box is its cell, so the init takes the cell over and the box is new
// exactly when the cell was; each field given moves into its field of the
// box.
void idr::CellInitOp::getFlowEdges(FlowEdges &edges) {
  Value box = getResult();
  edges.flow(FlowPoint::of(getCellMutable()), FlowPoint::of(box));
  builtEdges(box, getDataType(), getTag(), getFieldsMutable(), getHoles(), edges);
}

// The box is taken over: its cell becomes the token, and each field moves
// out of it.
void idr::TakeOp::getFlowEdges(FlowEdges &edges) {
  OpOperand &value = getValueMutable();
  DataType data = getDataType();
  Tag tag = getTag();
  edges.flow(FlowPoint::of(value), FlowPoint::of(getToken()));
  for (auto [i, field] : llvm::enumerate(getFields()))
    edges.flow(FlowPoint::partOf(value, FlowAnchor::fieldOf(data, tag, static_cast<unsigned>(i))),
               FlowPoint::of(Value(field)));
}

// The value, which has no cell of its own, is taken over: each field moves
// out of it. A constructor none of whose fields holds a reference (none at
// all, or only words) moves no reference on, so its value is given up
// whole: else the unpack would read as a borrow of it.
void idr::UnpackOp::getFlowEdges(FlowEdges &edges) {
  OpOperand &value = getValueMutable();
  DataType data = getDataType();
  Tag tag = getTag();
  if (llvm::none_of(getFields(), [](Value field) { return holdsReferences(field.getType()); }))
    edges.release(value);
  for (auto [i, field] : llvm::enumerate(getFields()))
    edges.flow(FlowPoint::partOf(value, FlowAnchor::fieldOf(data, tag, static_cast<unsigned>(i))),
               FlowPoint::of(Value(field)));
}

// An allocation's buffer is plain: the reference the result takes is new.
void idr::OwnAdoptOp::getFlowEdges(FlowEdges &edges) { edges.fresh(getResult()); }

// The reference goes to the store that writes the result, which no edge
// follows; the result is the value, read.
void idr::OwnGiveOp::getFlowEdges(FlowEdges &edges) {
  edges.release(getValueMutable());
  edges.flow(FlowPoint::of(getValue()), FlowPoint::of(getResult()));
}

//===----------------------------------------------------------------------===//
// Upstream's ops
//===----------------------------------------------------------------------===//

namespace {

// The model of `Op`, whose edges `edgesOf` adds.
template <typename Op, void (*edgesOf)(Op, FlowEdges &)>
struct Model : FlowOpInterface::ExternalModel<Model<Op, edgesOf>, Op> {
  void getFlowEdges(Operation *op, FlowEdges &edges) const { edgesOf(cast<Op>(op), edges); }
};

// The tensor an insert makes is its destination with one element moved in.
void insertEdges(tensor::InsertOp insert, FlowEdges &edges) {
  Value made = insert.getResult();
  edges.flow(FlowPoint::of(insert.getScalarMutable()),
             FlowPoint::partOf(made, elementsOf(made.getType())));
  edges.flow(FlowPoint::of(insert.getDest()), FlowPoint::of(made));
}

void extractEdges(tensor::ExtractOp extract, FlowEdges &edges) {
  Value tensor = extract.getTensor();
  edges.flow(FlowPoint::partOf(tensor, elementsOf(tensor.getType())),
             FlowPoint::of(extract.getResult()));
}

// A store writes an element over the one it replaces, which the lowering
// releases; the value's reference comes to it through idr.own.give, so it
// only reads the value.
void storeEdges(memref::StoreOp store, FlowEdges &edges) {
  Value buffer = store.getMemRef();
  edges.flow(FlowPoint::of(store.getValue()), FlowPoint::partOf(buffer, elementsOf(buffer.getType())));
  edges.overwrite(FlowPoint::partOf(buffer, elementsOf(buffer.getType())));
}

// A load reads an element out of its buffer, which keeps it.
void loadEdges(memref::LoadOp load, FlowEdges &edges) {
  Value buffer = load.getMemRef();
  edges.flow(FlowPoint::partOf(buffer, elementsOf(buffer.getType())),
             FlowPoint::of(load.getResult()));
}

void fromElementsEdges(tensor::FromElementsOp made, FlowEdges &edges) {
  Value tensor = made.getResult();
  for (OpOperand &use : made->getOpOperands())
    edges.flow(FlowPoint::of(use), FlowPoint::partOf(tensor, elementsOf(tensor.getType())));
  edges.fresh(tensor);
}

void splatEdges(tensor::SplatOp splat, FlowEdges &edges) {
  Value tensor = splat.getResult();
  edges.flow(FlowPoint::of(splat.getInputMutable()),
             FlowPoint::partOf(tensor, elementsOf(tensor.getType())));
  edges.fresh(tensor);
}

// The yield of a pad or a generate is an element of the tensor its parent
// makes.
void yieldEdges(tensor::YieldOp yield, FlowEdges &edges) {
  Value tensor = yield->getParentOp()->getResult(0);
  edges.flow(FlowPoint::of(yield.getValueMutable()),
             FlowPoint::partOf(tensor, elementsOf(tensor.getType())));
}

// A poison is no value the program computes: nothing else holds it, and it
// holds no label.
void poisonEdges(ub::PoisonOp poison, FlowEdges &edges) { edges.fresh(poison.getResult()); }

// Code past ub.unreachable never runs, so it has no effect a caller could
// observe; upstream declares none at all, which a reader of effects would
// take for any.
struct NeverRuns : MemoryEffectOpInterface::ExternalModel<NeverRuns, ub::UnreachableOp> {
  void getEffects(Operation *, SmallVectorImpl<MemoryEffects::EffectInstance> &) const {}
};

} // namespace

void idr::registerFlowInterfaceExternalModels(DialectRegistry &registry) {
  registry.addExtension(+[](MLIRContext *context, tensor::TensorDialect *) {
    tensor::InsertOp::attachInterface<Model<tensor::InsertOp, insertEdges>>(*context);
    tensor::ExtractOp::attachInterface<Model<tensor::ExtractOp, extractEdges>>(*context);
    tensor::FromElementsOp::attachInterface<Model<tensor::FromElementsOp, fromElementsEdges>>(
        *context);
    tensor::SplatOp::attachInterface<Model<tensor::SplatOp, splatEdges>>(*context);
    tensor::YieldOp::attachInterface<Model<tensor::YieldOp, yieldEdges>>(*context);
  });
  registry.addExtension(+[](MLIRContext *context, memref::MemRefDialect *) {
    memref::LoadOp::attachInterface<Model<memref::LoadOp, loadEdges>>(*context);
    memref::StoreOp::attachInterface<Model<memref::StoreOp, storeEdges>>(*context);
  });
  registry.addExtension(+[](MLIRContext *context, ub::UBDialect *) {
    ub::PoisonOp::attachInterface<Model<ub::PoisonOp, poisonEdges>>(*context);
    ub::UnreachableOp::attachInterface<NeverRuns>(*context);
  });
}
