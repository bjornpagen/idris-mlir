// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a run of each function may do besides computing its results: the
// dialect's Effect bits, held once, as each idr.func's `effects`, its entry
// (absent until a pass has found it, when the function may do anything, as
// Func.h's effectsOf reads it for a call). Once the program is first-order
// a function runs the callee of each idr.call in its body and nothing
// else: a force is a call of its memo sum's dispatch function, which calls
// the label. So the bits flow along upstream's call graph alone, and the
// solve is one pass over its components, callees first. A call carries no
// copy: what it may do is its callee's.
//
// There is one driver, componentEffects, over one component whose callees
// outside it are final: solveEffects runs it over every component of a
// program, and idr-optimize's ready set runs it on each component when the
// component is final.
//
// Before defunctionalization's conversion one question is asked of the
// effects, and it is not about the bits: which labels run at every force.
// That is a reach over the label solve's graph, which only the label solve
// knows (observableRuns).
#ifndef IDR_ANALYSIS_EFFECTS_H
#define IDR_ANALYSIS_EFFECTS_H

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Func.h"

#include "mlir/Analysis/CallGraph.h"
#include "mlir/IR/SymbolTable.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLFunctionalExtras.h"
#include "llvm/ADT/SmallVector.h"

namespace idr {

// What a run of `fn` may do: its entry, or anything while it has none.
inline idr::Effect entryOf(idr::FuncOp fn) {
  idr::EffectAttr effects = fn.getEffectsAttr();
  return effects ? effects.getValue() : anyEffect;
}

// Gives `fn` the entry `effect`. The full set is no attribute, the one form
// a function that may do anything holds; an equal entry is left as it is.
void setEntry(idr::FuncOp fn, idr::Effect effect);

// The components of `graph`, upstream's call graph of a program, callees
// first, each as its functions. A component's callees outside it come in
// an earlier component; the order is a function of the program alone.
llvm::SmallVector<llvm::SmallVector<idr::FuncOp>>
callGraphComponents(const mlir::CallGraph &graph);

// What every member of `component`, a component of the call graph, may do:
// what each member's body does itself, and what each callee outside the
// component may do, as its entry stands. Every such callee is final when
// this is asked, so its entry will not change. A call to a member
// carries nothing new: that member's own part is in the sum.
//
// A body's own part: diverge unless Idris proved its function total; crash
// where an op may crash; IO where it forges a world or a parameter may
// hold one, since a world reaches a function no other way. It reads the
// members' bodies, `symbols` to resolve a callee and nothing else, so
// disjoint components may be asked from different workers.
idr::Effect componentEffects(llvm::ArrayRef<idr::FuncOp> component,
                             const mlir::SymbolTable &symbols);

// The driver over a whole first-order program: every function gets its
// component's componentEffects as its entry, bottom-up over the call graph
// of `program` as it stands.
void solveEffects(idr::ProgramOp program);

// Before the conversion: appends to `labels` the label functions `op`, an
// idr.apply or an idr.force, may run, those of the key of its callee or its
// cell. Called from worker threads; it only reads.
using LabelsRun =
    llvm::function_ref<void(mlir::Operation *op, llvm::SmallVectorImpl<idr::FuncOp> &labels)>;

// Before the conversion: the functions whose run may perform an effect the
// program's outside observes (an op of the ObservableIO class), in its body
// or in what it runs, a call's callee or the labels of an apply or a force.
// A memo label among them runs at every force, so that its effect happens
// where the value is demanded: it is `by_name`.
llvm::DenseSet<idr::FuncOp> observableRuns(idr::ProgramOp program,
                                           const mlir::SymbolTable &symbols, LabelsRun labelsRun);

} // namespace idr

#endif // IDR_ANALYSIS_EFFECTS_H
