// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a run of each function may do besides computing its results, held
// once: the dialect's Effect bits, and whether the run may perform an
// effect the program's outside observes. A function runs the callee of
// each idr.call in its body and the labels of each idr.apply and idr.force:
// an apply calls one label of its callee's key, and a force may run one
// label of its cell's key. Making a closure or a suspension runs nothing,
// so what a label may do counts where it is applied or forced, never where
// it is made. That is also why a call's own `effects` is its callee's: no
// closure is passed to a call once the closures are sums, and a callee
// that applies or forces one already counts its labels.
//
// The bits flow from a function to every function that runs it, and the
// solve is one pass over the components of that graph, callees first.
// Defunctionalization solves it first, on the whole module, right after
// its label solve, since only that solve knows what an apply or a force
// runs. Then the ready set rewrites each component's entries once the
// component is final, when a force's labels are the constructors of the
// memo sum its cell has become.
#ifndef IDR_ANALYSIS_EFFECTS_H
#define IDR_ANALYSIS_EFFECTS_H

#include "idr/IR/IdrDialect.h"
#include "idr/Analysis/Holds.h"

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/SymbolTable.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLFunctionalExtras.h"
#include "llvm/ADT/SmallVector.h"

namespace idr {

// Everything a call may do: what an absent `effects` means, and what no
// writer stores.
constexpr idr::Effect anyEffect = idr::Effect::io | idr::Effect::crash | idr::Effect::diverge;

// What a run of a function may do. `observable` is narrower than `io`: an
// array, a buffer and a forged world are IO in the world's order that only
// the program reads back.
struct EffectSummary {
  idr::Effect effect = idr::Effect::none;
  bool observable = false;

  bool operator==(const EffectSummary &other) const = default;
};

// Before defunctionalization's conversion: appends to `labels` the label
// functions `op`, an idr.apply or an idr.force, may run, those of the key of
// its callee or its cell. Called from worker threads; it only reads.
using LabelsRun =
    llvm::function_ref<void(mlir::Operation *op, llvm::SmallVectorImpl<idr::FuncOp> &labels)>;

// The summary of every function of a module before the conversion, solved
// in the constructor and never changed afterwards.
//
// A function's own part: diverge unless Idris proved it total; crash where
// an op may crash; IO where it forges a world or a parameter may hold one,
// since a world reaches a function no other way; observable where an op's
// class says the outside observes it. What it runs adds the runner's
// summary: all of it through a call or an apply, which runs the label's
// body. Through a force, the bits all the same, since forcing a cell may
// run its label; but the observable bit only from a label that is
// `by_name`: a cell that keeps its value performs its effect at its first
// force alone, so forcing it again repeats nothing, and a `by_name` cell
// runs its label at every force.
//
// A label is static when a constant of the module names it as a
// suspension, a closure constant that captures every parameter of its
// function: a top-level constant names one value of the program, evaluated
// once, so its effect is observed that once and its cell keeps its value.
class ModuleEffects {
public:
  ModuleEffects(mlir::ModuleOp module, const Holds &holds, const mlir::SymbolTable &symbols,
                LabelsRun labelsRun);

  // Whether `label`, a label of a memo key, runs at every force: a run of
  // it may be observed, and it is not static.
  bool byName(idr::FuncOp label) const;

  // Gives every function its summary's bits as its `effects`, the full set
  // as no attribute, and every idr.call its callee's: a call's `effects` is
  // its callee's wherever the module is verified. Call it once the
  // conversion has made every call it makes. The ready set writes both
  // again from final bodies, which only remove what a function runs.
  void writeEntries() const;

private:
  unsigned position(idr::FuncOp fn) const;
  bool byNameAt(unsigned at) const;

  const mlir::SymbolTable &symbols;
  // In module order.
  llvm::SmallVector<idr::FuncOp> functions;
  llvm::DenseMap<mlir::Operation *, unsigned> positions;
  llvm::SmallVector<EffectSummary> summaries;
  llvm::DenseSet<mlir::Operation *> statics;
};

// After the conversion: appends to `labels` the label functions `force` may
// run, the label constructors of the memo sum its cell is, each named by its
// function. A graph whose order the ready set follows has these edges
// beside the calls', so a label is final before a function that forces it.
void forcedLabels(idr::ForceOp force, const mlir::SymbolTable &symbols,
                  llvm::SmallVectorImpl<idr::FuncOp> &labels);

// When `component`, a strongly connected component of the ready set's graph,
// becomes ready: every idr.call in a member whose callee is outside it takes
// that callee's entry, final by then, as its own `effects`. Canonicalize and
// CSE read a call's effects, so the calls get them before the component's
// one cleanup, not after it.
void writeCallEffectsOnReady(llvm::ArrayRef<idr::FuncOp> component,
                             const mlir::SymbolTable &symbols);

// When every member of `component` is final: their entry, from their final
// bodies and the entries of what they run outside the component, written
// on each member; then every idr.call between members takes it. After the
// conversion a force runs the labels its memo sum names, and no apply is
// left. Only the bits are written: the observable bit has no reader once
// the memo sums are made.
void writeEntriesOnFinal(llvm::ArrayRef<idr::FuncOp> component, const Holds &holds,
                         const mlir::SymbolTable &symbols);

} // namespace idr

#endif // IDR_ANALYSIS_EFFECTS_H
