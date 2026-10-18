// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a run of each function may do besides computing its results: the
// dialect's Effect bits, held as the `effects` property of each idr.func,
// its entry (everything, idr::anyEffect, until a pass has found less), and
// of each idr.call. A call carries its callee's effects, as an llvm.call
// carries its memory effects, so that MLIR's own effects question has its
// answer at the call. idr::writeEffects (Func.h) is the one writer, of a
// function's effects and every call's of it at once: one written without
// the other would leave a call the verifier refuses.
// Once the program is first-order a function runs the callee of each
// idr.call in its body and nothing else: a force is a call of its memo sum's
// dispatch function, which calls the label. So the bits flow along
// upstream's call graph alone, and the solve is one pass over its cycles
// of calls (CallCycles), callees first.
//
// What one component may do is idr::componentEffects (Func.h), over one
// component whose callees outside it are final: solveEffects asks it of
// every component of a program, and idr-optimize's ready set of each
// component when the component is final.
//
// Before defunctionalization's conversion one question is asked of the
// effects, and it is not about the bits: which labels run at every force.
// That is a reach over the label solve's graph, which only the label solve
// knows (observableRuns).
#ifndef IDR_ANALYSIS_EFFECTS_H
#define IDR_ANALYSIS_EFFECTS_H

#include "idr/Analysis/CallCycles.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/SymbolTable.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLFunctionalExtras.h"
#include "llvm/ADT/SmallVector.h"

namespace idr {

// The driver over a whole first-order program: through the components of
// its call graph, callees first, every member of a component gets the
// component's componentEffects as its entry, and every call of it the
// same, before any caller's component is solved.
void solveEffects(idr::ProgramOp program, const CallCycles &cycles);

// Before the conversion: appends to `labels` the label functions `runner`
// may run, those of the key of its label carrier. Called from worker
// threads; it only reads.
using LabelsRun = llvm::function_ref<void(idr::RunsLabelsOpInterface runner,
                                          llvm::SmallVectorImpl<idr::FuncOp> &labels)>;

// Before the conversion: the functions whose run may perform an effect the
// program's outside observes (an op of the ObservableIO class), in its body
// or in what it runs, a call's callee or the labels an apply or a force
// runs. A memo label among them runs at every force, so that its effect
// happens where the value is demanded: it is `by_name`.
llvm::DenseSet<idr::FuncOp> observableRuns(idr::ProgramOp program,
                                           const mlir::SymbolTable &symbols, LabelsRun labelsRun);

} // namespace idr

#endif // IDR_ANALYSIS_EFFECTS_H
