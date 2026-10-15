// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// How a value moves, read: the values a branch or a region branch forwards,
// as upstream's interfaces say; every edge of an op, what it declares
// through the flow interface (FlowEdges.h) and what upstream's interfaces
// declare for it; and the flow rule the verifier holds a function to while
// it may hold closures and suspensions. The label solve, the key decision
// of idr-defunctionalize, the escape analysis, exclusivity, `consumes` and
// the owned walk read these edges, each those of the carrier it asks about.
//
// Every op of ours with an edge to declare holds the interface in its ODS;
// the upstream ops that move a value into or out of the elements of a
// tensor, or make one from nothing, hold it as an external model, attached
// by registerFlowInterfaceExternalModels.
//
// Then what an op does besides computing its results, which the passes
// that move ops ask (lib/IR/Effects.cpp): whether it only computes, and
// whether it may perform IO, a call counted as its callee's effects where
// the asker has the program's symbol table.
#ifndef IDR_IR_FLOW_H
#define IDR_IR_FLOW_H

#include "idr/IR/FlowEdges.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/DialectRegistry.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/IR/Value.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "llvm/ADT/STLFunctionalExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <optional>

namespace idr {

// Each operand `op` forwards unchanged, with each value it becomes there,
// in successor order: a branch's forwarded operands and the arguments of
// the blocks it goes to, after those the branch produces; a region branch's
// entry operands, and the operands of a terminator of one of its regions,
// and the region arguments or results they become, as
// RegionBranchOpInterface says for each successor. An operand may become
// one value per successor. A forwarded operand moves on with what it holds:
// its reference too.
void forwardedValues(mlir::Operation *op,
                     llvm::function_ref<void(mlir::OpOperand &operand, mlir::Value input)> each);

// Whether upstream's interfaces or ours say every move `op` makes: it holds
// the flow interface, it is a branch, a region branch or a terminator of
// one, or it selects one of two values (SelectLikeOpInterface). Any other
// op is unknown to the readers that follow references: what it takes may
// go anywhere, and what it gives may be shared.
bool declaresFlow(mlir::Operation *op);

// Adds to `edges` every edge of `op`: those it declares through the flow
// interface; each forwarded value, a Flow from the use to the value it
// becomes; and for a select, a Flow from each value it may choose, which
// it reads, to its result.
void flowEdgesOf(mlir::Operation *op, FlowEdges &edges);

// The flow rule of `fn`'s body, while its program may hold closures and
// suspensions (stage higher); at any later stage there is nothing to check,
// and a function outside a program is past every stage. An op with the
// flow interface: each edge names ends it may, from a use of its own or a
// value or part of one of its operands, a parameter or a result, to one of
// its results or region arguments or a part of one, a part of an operand's
// value or of a value of its parent (a terminator's), a parameter or a
// result; an edge that carries labels joins two ends of one carrier type
// (the type without its grade). Any other op: every operand, result and
// block argument that holds labels is forwarded, chosen by a select, or a
// successor input of a region branch, or an argument of a non-entry block.
// Fails with an error at the op naming the edge or the value otherwise.
mlir::LogicalResult verifyFlow(FuncOp fn);

// Attaches the flow interface to the upstream ops that move a value into or
// out of the elements of a tensor or make one from nothing: tensor.insert,
// tensor.extract, tensor.from_elements, tensor.splat, tensor.yield,
// ub.poison. Every registry a module is read with takes it.
void registerFlowInterfaceExternalModels(mlir::DialectRegistry &registry);

// What a call may do is its callee's effects, the `effects` its idr.func
// holds: the one copy, which only the program's symbol table reaches. A
// call declares every effect a function may have, so a reader without the
// table, an upstream pass among them, never drops, merges or moves one. A
// reader that has the table, built once for its run, gives it to the
// queries below, which then count a call as its callee's effects; one
// without gives none, and a call may then do anything. No function's
// `effects` or the table may change while a query reads them.
struct CalleeEffects {
  const mlir::SymbolTable &symbols;
};

// The memory effects `op` has itself, its nested ops aside, as
// MemoryEffectOpInterface declares them, except that a call whose callee
// `callees` names as an idr.func has the effects on the IO, crash and
// divergence resources its callee's `effects` say. Empty for an op whose
// effects are its regions' (RecursiveMemoryEffects) and for ub.unreachable,
// which never runs; none when MLIR knows nothing of what `op` does.
std::optional<llvm::SmallVector<mlir::MemoryEffects::EffectInstance>>
ownEffects(mlir::Operation *op, const CalleeEffects *callees);

// Whether `op`, with everything in it, only computes: its effects are at
// most the allocation of its own results, so it may move across any op,
// run on fewer paths, or not at all.
bool onlyAllocates(mlir::Operation *op, const CalleeEffects *callees);

// Whether `op`, or something in it, may perform IO: an effect on the IO
// resource. An op that does not may run later, past ops that only compute,
// though it may crash or not return.
bool performsIO(mlir::Operation *op, const CalleeEffects *callees);

} // namespace idr

#endif // IDR_IR_FLOW_H
