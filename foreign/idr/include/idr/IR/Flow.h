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
// whose verifier holds its edges to their rule (detail::verifyFlowEdges);
// the upstream ops that move a value into or out of the elements of a
// tensor or a buffer, or make one from nothing, hold it as an external
// model, attached by registerFlowInterfaceExternalModels.
//
// Then what an op does besides computing its results, which the passes
// that move ops ask (lib/IR/Effects.cpp), read from MLIR's memory effects
// alone: a call holds its own.
#ifndef IDR_IR_FLOW_H
#define IDR_IR_FLOW_H

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/DialectRegistry.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/Value.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "llvm/ADT/STLFunctionalExtras.h"

#include <cstdint>

namespace idr {

// Each operand `op` forwards unchanged, with each value it becomes there,
// in successor order: a region branch's entry operands, and the operands of
// a terminator of one of its regions, and the region arguments or results
// they become, as RegionBranchOpInterface says for each successor. An
// operand may become one value per successor. A forwarded operand moves on
// with what it holds: its reference too.
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
// tensor.yield, memref.load, ub.poison; and to ub.unreachable the memory
// effects interface, with none, which upstream does not declare. Every
// registry a module is read with takes it. No interface verifier reaches an
// external model; a unit test holds each to the rule of
// detail::verifyFlowEdges.
void registerFlowInterfaceExternalModels(mlir::DialectRegistry &registry);

// What an op, with everything in it, does as one asker sees it, ordered:
// only computes; has an effect the asker ignores; touches what it asks
// about, or does what MLIR cannot say (no answer from
// mlir::getEffectsRecursively). An allocation of the op's own results is
// computing.
enum class Does : std::uint8_t { Computes, Effects, Touches };
Does classify(mlir::Operation *op,
              llvm::function_ref<bool(const mlir::MemoryEffects::EffectInstance &,
                                      mlir::Operation *)>
                  touches);

// Whether `op`, with everything in it, only computes: its effects are at
// most the allocation of its own results, so it may move across any op,
// run on fewer paths, or not at all. classify(op, nothing touched) is
// Computes.
bool onlyAllocates(mlir::Operation *op);

// Whether `op`, or something in it, may perform IO: a read or a write of
// the IO resource touches. An op that does not may run later, past ops that
// only compute, though it may crash or not return.
bool performsIO(mlir::Operation *op);

// Whether `call` may run at `at`, an op after it in its block, in place of
// where it is: nothing between can tell. What a call reads is its
// arguments and what each is the same value as or a part of (sourceOf); an
// op between that writes or frees one of those, as a drop of the value a
// borrowed argument views does, could tell. A call that only computes (its
// effects are none: no IO, no crash, and it returns) may run after
// anything else between; any other only after ops that perform no IO,
// which its crash or its loop would be ordered with, and that write or
// free only memory made after it, which nothing it is given reaches.
// Raising asks it of a call whose result it takes to its consumer, and
// idr-trmc of a call it moves to the end of a tail.
bool mayRunAt(CallOp call, mlir::Operation *at);

} // namespace idr

#endif // IDR_IR_FLOW_H
