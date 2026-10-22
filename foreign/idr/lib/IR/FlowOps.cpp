// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The edges of each op of ours that holds the flow interface and whose
// area keeps no edges of its own (counting's are lib/IR/Counting/Flow.cpp),
// and of the upstream ops that move a value into or out of the elements of
// a tensor or a buffer or make one from nothing, which hold it as an
// external model: where what each holds, takes or gives moves, as data
// (FlowEdges.h). A value is followed whole, or into and out of a part of
// another (a field, the elements, the forced state, a capture, a hole).

#include "idr/IR/Flow.h"

#include "idr/IR/Families/Families.h"
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

// Each field given moves into its field of the value built, which takes it
// over: what a constructor, a cell's init and a rebuild declare alike.
void idr::builtEdges(Value value, DataType data, Tag tag, MutableOperandRange fields,
                     ArrayRef<int32_t> holes, FlowEdges &edges) {
  unsigned given = 0;
  for (unsigned i = 0, n = static_cast<unsigned>(data.ctor(tag).fields.size()); i < n; ++i) {
    if (llvm::is_contained(holes, static_cast<int32_t>(i)))
      continue;
    edges.flow(FlowSource::of(fields[given++]),
               FlowPlace::partOf(value, FlowAnchor::fieldOf(data, tag, i)));
  }
}

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
    edges.flow(FlowSource::of(captures[i]), FlowPlace::parameter(label, i), Carriers::labels());
    edges.flow(FlowSource::of(captures[i]),
               FlowPlace::partOf(self, FlowAnchor::captureOf(carrier, i)), Carrier::Reference);
  }
  edges.fresh(self);
}

// An op that hands its operand to its result: the result is the operand's
// value, and the op takes it over.
void handOn(OpOperand &use, Value result, FlowEdges &edges) {
  edges.flow(FlowSource::of(use), FlowPlace::of(result));
}

// A numeral and the natural it is converted to or from are one value where
// the numeral's bound is open, so it is held as that natural: the
// reference goes on. A numeral of a fixed width is a word, which holds no
// reference, and the other side is a value the conversion makes, the
// operand only read: a natural it builds, or a word. Essential: the two are
// the ways a numeral can be held.
void numeralEdges(OpOperand &use, Value result, Type numeral, FlowEdges &edges) {
  if (dataTypeOf(numeral).layout() == families::Layout::Natural)
    handOn(use, result, edges);
  else
    edges.fresh(result);
}

} // namespace

// A call moves its arguments into its callee's parameters, which take them
// over where they are owned; its results are its callee's.
void idr::CallOp::getFlowEdges(FlowEdges &edges) {
  FlatSymbolRefAttr callee = getCalleeAttr();
  MutableOperandRange args = getArgsMutable();
  for (unsigned i = 0, n = args.size(); i < n; ++i)
    edges.flow(FlowSource::of(args[i]), FlowPlace::parameter(callee, i));
  for (OpResult result : getOperation()->getResults())
    edges.flow(FlowSource::result(callee, result.getResultNumber()), FlowPlace::of(Value(result)));
}

void idr::ReturnOp::getFlowEdges(FlowEdges &edges) {
  auto fn = FlatSymbolRefAttr::get(cast<FuncOp>(getOperation()->getParentOp()).getSymNameAttr());
  for (OpOperand &use : getOperation()->getOpOperands())
    edges.flow(FlowSource::of(use), FlowPlace::result(fn, use.getOperandNumber()));
}

// A constant's parts are expanded where it is held, by the reader that
// follows them: a closure is a label, a constructor holds its fields at
// their anchors, and static data is every copy's.
void idr::ConstantOp::getFlowEdges(FlowEdges &edges) { edges.constant(getValue(), getResult()); }

// A constructor value is new, built of the fields given; it has no hole,
// which only a cell has.
void idr::DataConOp::getFlowEdges(FlowEdges &edges) {
  Value value = getResult();
  builtEdges(value, getDataType(), getTag(), getFieldsMutable(), {}, edges);
  edges.fresh(value);
}

// A read of a field gives what the field holds; the value is only read.
void idr::DataFieldOp::getFlowEdges(FlowEdges &edges) {
  FlowAnchor field =
      FlowAnchor::fieldOf(getDataType(), getTag(), static_cast<unsigned>(getIndex()));
  edges.flow(FlowSource::partOf(getValue(), field), FlowPlace::of(getResult()));
}

// The tag is read, and nothing moves.
void idr::DataTagOp::getFlowEdges(FlowEdges &) {}

// A value at a type its refinements make equal to its own is the same
// value: the reference goes on.
void idr::DataReindexOp::getFlowEdges(FlowEdges &edges) {
  handOn(getValueMutable(), getResult(), edges);
}

void idr::NumeralToNatOp::getFlowEdges(FlowEdges &edges) {
  numeralEdges(getValueMutable(), getResult(), getValue().getType(), edges);
}

void idr::NumeralOfNatOp::getFlowEdges(FlowEdges &edges) {
  numeralEdges(getValueMutable(), getResult(), getType(), edges);
}

// The value moves into the hole the destination writes.
void idr::DestWriteOp::getFlowEdges(FlowEdges &edges) {
  TypedValue<DestType> dest = getDest();
  edges.flow(FlowSource::of(getValueMutable()),
             FlowPlace::partOf(dest, FlowAnchor::holeOf(dest.getType())));
}

// Each answer is what the region wrote through the destination it receives
// for it, read out of the hole when the region ends. A destination holds no
// reference, so that it is new to the region declares no edge: the place is
// this op's alone, and that it is written once is its type's.
void idr::DestAnswerOp::getFlowEdges(FlowEdges &edges) {
  for (auto [dest, answer] : llvm::zip_equal(getBody().getArguments(), getResults()))
    edges.flow(FlowSource::partOf(dest, FlowAnchor::holeOf(cast<DestType>(dest.getType()))),
               FlowPlace::of(answer));
}

void idr::FnClosureOp::getFlowEdges(FlowEdges &edges) { labelEdges(*this, edges); }

// A suspension's label returns into the forced state of its type, the one
// slot every force of a cell of that type reads.
void idr::LazySuspendOp::getFlowEdges(FlowEdges &edges) {
  labelEdges(*this, edges);
  edges.unify(FlowPlace::result(getCalleeAttr(), 0),
              FlowPlace::partOf(getResult(), forcedOf(getType())));
}

// An evaluated suspension holds its value in its forced state and runs no
// label.
void idr::LazyDelayOp::getFlowEdges(FlowEdges &edges) {
  edges.flow(FlowSource::of(getValueMutable()),
             FlowPlace::partOf(getResult(), forcedOf(getType())));
  edges.fresh(getResult());
}

// A force reads the forced state of its cell.
void idr::LazyForceOp::getFlowEdges(FlowEdges &edges) {
  Value cell = getSuspension();
  edges.flow(FlowSource::partOf(cell, forcedOf(cell.getType())), FlowPlace::of(getResult()));
}

void idr::FnApplyOp::getFlowEdges(FlowEdges &edges) { edges.dispatch(*this); }

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

// A cast into or out of a linear position: the value goes on.
void idr::LinCastOp::getFlowEdges(FlowEdges &edges) {
  handOn(getValueMutable(), getResult(), edges);
}

// A cell in the frame is the frame's, lent to whatever holds it: it is new
// to no one, so nothing is declared, and its box is not fresh.
void idr::CellStackOp::getFlowEdges(FlowEdges &) {}

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
  edges.flow(FlowSource::of(insert.getScalarMutable()),
             FlowPlace::partOf(made, elementsOf(made.getType())));
  edges.flow(FlowSource::of(insert.getDest()), FlowPlace::of(made));
}

void extractEdges(tensor::ExtractOp extract, FlowEdges &edges) {
  Value tensor = extract.getTensor();
  edges.flow(FlowSource::partOf(tensor, elementsOf(tensor.getType())),
             FlowPlace::of(extract.getResult()));
}

// A store writes an element over the one it replaces, which the lowering
// releases; the value's reference comes to it through idr.own.give, so it
// only reads the value.
void storeEdges(memref::StoreOp store, FlowEdges &edges) {
  Value buffer = store.getMemRef();
  edges.flow(FlowSource::of(store.getValue()),
             FlowPlace::partOf(buffer, elementsOf(buffer.getType())));
  edges.overwrite(buffer, elementsOf(buffer.getType()));
}

// A load reads an element out of its buffer, which keeps it.
void loadEdges(memref::LoadOp load, FlowEdges &edges) {
  Value buffer = load.getMemRef();
  edges.flow(FlowSource::partOf(buffer, elementsOf(buffer.getType())),
             FlowPlace::of(load.getResult()));
}

void fromElementsEdges(tensor::FromElementsOp made, FlowEdges &edges) {
  Value tensor = made.getResult();
  for (OpOperand &use : made->getOpOperands())
    edges.flow(FlowSource::of(use), FlowPlace::partOf(tensor, elementsOf(tensor.getType())));
  edges.fresh(tensor);
}

void splatEdges(tensor::SplatOp splat, FlowEdges &edges) {
  Value tensor = splat.getResult();
  edges.flow(FlowSource::of(splat.getInputMutable()),
             FlowPlace::partOf(tensor, elementsOf(tensor.getType())));
  edges.fresh(tensor);
}

// The yield of a pad or a generate is an element of the tensor its parent
// makes.
void yieldEdges(tensor::YieldOp yield, FlowEdges &edges) {
  Value tensor = yield->getParentOp()->getResult(0);
  edges.flow(FlowSource::of(yield.getValueMutable()),
             FlowPlace::partOf(tensor, elementsOf(tensor.getType())));
}

// A poison is no value the program computes: nothing else holds it, and it
// holds no label.
void poisonEdges(ub::PoisonOp poison, FlowEdges &edges) { edges.fresh(poison.getResult()); }

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
  });
}
