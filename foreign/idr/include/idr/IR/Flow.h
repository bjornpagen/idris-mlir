// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// How a value moves, read: the values a region branch forwards, as
// upstream's interface says; every edge of an op, what it declares through
// the flow interface (FlowEdges.h) and what upstream's interfaces declare
// for it; and the flow rule the verifier holds a function to while it may
// hold closures and suspensions. The label solve, the key decision of
// idr-defunctionalize, the escape analysis, exclusivity, counting's one
// rule (referenceAt, movedOn: a counted operand's reference moves on where
// an edge hands the use on, or a part of it the op takes over, or gives it
// up) and the lifetimes' decide step read these edges, each those of the
// carrier it asks about. An idr.func's body is one block, so no branch
// forwards a value in one.
//
// Every op of ours with an edge to declare holds the interface in its ODS,
// whose verifier holds its edges to their rule (verifyFlowEdges);
// the upstream ops that move a value into or out of the elements of a
// tensor or a buffer, or make one from nothing, hold it as an external
// model, attached by registerFlowInterfaceExternalModels. What an op does
// besides moving values is the effect system's query API to say
// (idr/IR/Effects/Whole.h), never this header's.
#ifndef IDR_IR_FLOW_H
#define IDR_IR_FLOW_H

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/DialectRegistry.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/Value.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <concepts>

namespace idr {

namespace detail {

// What `branch` forwards from `point`, the op itself or a terminator of one
// of its regions, to each of its successors. A jump through `branch` to an
// enclosing join point has a successor `branch` does not own, whose inputs
// are its owner's to say. The uses are taken from the range's base, as
// upstream's own readers of these interfaces take them: an empty range has
// no first operand to index from.
template <std::invocable<mlir::OpOperand &, mlir::Value> Each>
void forwardFrom(mlir::RegionBranchOpInterface branch, mlir::RegionBranchPoint point,
                 Each &each) {
  llvm::SmallVector<mlir::RegionSuccessor> successors;
  branch.getSuccessorRegions(point, successors);
  for (mlir::RegionSuccessor successor : successors) {
    mlir::OperandRange operands = branch.getSuccessorOperands(point, successor);
    llvm::MutableArrayRef<mlir::OpOperand> uses(operands.getBase(), operands.size());
    for (auto [use, input] : llvm::zip_equal(
             uses, mlir::getRegionBranchSuccessorOwner(successor).getSuccessorInputs(successor)))
      each(use, input);
  }
}

} // namespace detail

// Each operand `op` forwards unchanged, with each value it becomes there,
// in successor order: a region branch's entry operands, and the operands of
// a terminator of one of its regions, and the region arguments or results
// they become, as RegionBranchOpInterface says for each successor. An
// operand may become one value per successor, and a jump's successor is the
// join region its token designates, whose op owns the inputs. A forwarded
// operand moves on with what it holds: its reference too.
template <std::invocable<mlir::OpOperand &, mlir::Value> Each>
void forwardedValues(mlir::Operation *op, Each &&each) {
  if (auto branch = mlir::dyn_cast<mlir::RegionBranchOpInterface>(op))
    detail::forwardFrom(branch, mlir::RegionBranchPoint::parent(), each);
  if (auto terminator = mlir::dyn_cast<mlir::RegionBranchTerminatorOpInterface>(op))
    if (auto branch = mlir::dyn_cast_or_null<mlir::RegionBranchOpInterface>(op->getParentOp()))
      detail::forwardFrom(branch, mlir::RegionBranchPoint(terminator), each);
}

// The edges of a value built of fields: each field given (`fields`, the
// fields of constructor `tag` of `data` that are not `holes`, in order)
// moves into its field of `value`, which takes it over. What a constructor,
// a cell's init and a rebuild each declare.
void builtEdges(mlir::Value value, DataType data, Tag tag, mlir::MutableOperandRange fields,
                llvm::ArrayRef<int32_t> holes, FlowEdges &edges);

// The edges of a shaped value made full of one value: `fill` moves into
// every element of `made`, each holding it, so it is held as many times as
// `made` has elements; a value of rank 0 has one element, which takes it
// once. What a new array and a splat declare.
void everyElementEdges(mlir::OpOperand &fill, mlir::Value made, FlowEdges &edges);

// Whether upstream's interfaces or ours say every move `op` makes: it holds
// the flow interface, it is a region branch or a terminator of one, or it
// selects one of two values (SelectLikeOpInterface). Any other op is
// unknown to the readers that follow references: what it takes may go
// anywhere, and what it gives may be shared.
bool declaresFlow(mlir::Operation *op);

// Adds to `edges` every edge of `op`: those it declares through the flow
// interface; each forwarded value, a Flow from the use to the value it
// becomes; and for a select, a Flow from each value it may choose, which
// it reads, to its result.
void flowEdgesOf(mlir::Operation *op, FlowEdges &edges);

// The flow rule at one op of a function whose program may hold closures
// and suspensions (stage higher): the function verifier's one walk runs it
// at each op it meets, beside the row's derivation and the scope walk, and
// at any later stage, where no label moves, does not run it. An op with the
// interface is held to its own edges by the interface's verifier, at every
// stage, and passes. Any other op: every operand, result and block argument
// that holds labels is forwarded, chosen by a select, or a successor input
// of a region branch. Fails with an error at the op naming the value
// otherwise.
mlir::LogicalResult verifyFlowOf(mlir::Operation *op);

// Attaches the flow interface to the upstream ops that move a value into or
// out of the elements of a tensor or a buffer or make one from nothing:
// tensor.insert, tensor.extract, tensor.from_elements, tensor.splat,
// tensor.yield, memref.load, memref.store, ub.poison. Every registry a
// module is read with takes it. No interface verifier reaches an external
// model; a unit test holds each to the rule of verifyFlowEdges.
void registerFlowInterfaceExternalModels(mlir::DialectRegistry &registry);

} // namespace idr

#endif // IDR_IR_FLOW_H
