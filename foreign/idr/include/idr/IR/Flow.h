// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// How a value moves, read: the values a region branch forwards, as
// upstream's interface says; every edge of an op, what it declares through
// the flow interface (FlowEdges.h) and what upstream's interfaces declare
// for it; and the flow rule the verifier holds a function to while it may
// hold closures and suspensions. The label solve, the key decision of
// idr-defunctionalize, the escape analysis, exclusivity, `consumes` and the
// owned walk read these edges, each those of the carrier it asks about. An
// idr.func's body is one block, so no branch forwards a value in one.
//
// Every op of ours with an edge to declare holds the interface in its ODS,
// whose verifier holds its edges to their rule (verifyFlowEdges);
// the upstream ops that move a value into or out of the elements of a
// tensor or a buffer, or make one from nothing, hold it as an external
// model, attached by registerFlowInterfaceExternalModels. What an op does
// besides moving values is the effect system's one query API to say
// (idr/IR/Effects/), never this header's.
#ifndef IDR_IR_FLOW_H
#define IDR_IR_FLOW_H

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/DialectRegistry.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/Value.h"
#include "llvm/ADT/STLFunctionalExtras.h"

namespace idr {

// Each operand `op` forwards unchanged, with each value it becomes there,
// in successor order: a region branch's entry operands, and the operands of
// a terminator of one of its regions, and the region arguments or results
// they become, as RegionBranchOpInterface says for each successor. An
// operand may become one value per successor, and a jump's successor is the
// join region its token designates, whose op owns the inputs. A forwarded
// operand moves on with what it holds: its reference too.
void forwardedValues(mlir::Operation *op,
                     llvm::function_ref<void(mlir::OpOperand &operand, mlir::Value input)> each);

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

// The flow rule of `fn`'s body for the ops that do not hold the flow
// interface, while its program may hold closures and suspensions (stage
// higher); at any later stage no label moves. An op with the interface is
// held to its own edges by the interface's verifier, at every stage. Any
// other op: every operand, result and block argument that holds labels is
// forwarded, chosen by a select, or a successor input of a region branch.
// Fails with an error at the op naming the value otherwise.
mlir::LogicalResult verifyFlow(FuncOp fn);

// Attaches the flow interface to the upstream ops that move a value into or
// out of the elements of a tensor or a buffer or make one from nothing:
// tensor.insert, tensor.extract, tensor.from_elements, tensor.splat,
// tensor.yield, memref.load, memref.store, ub.poison; and to
// ub.unreachable the memory effects interface, with none, which upstream
// does not declare. Every
// registry a module is read with takes it. No interface verifier reaches an
// external model; a unit test holds each to the rule of
// verifyFlowEdges.
void registerFlowInterfaceExternalModels(mlir::DialectRegistry &registry);

} // namespace idr

#endif // IDR_IR_FLOW_H
