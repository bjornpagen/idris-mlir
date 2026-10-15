// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Which boxes may outlive the frame that builds them, and which functions
// may have more than one frame live at a time: what idr-stack decides by.
//
// A reference to a cell is held by SSA values and parameters, and by the
// fields of other cells and of unboxed sums. Each value that may hold one
// stands in two ways: for the reference it holds (shallow), and for
// everything reachable from it through fields, its own reference too
// (deep). An unboxed sum has no reference of its own, so it stands only
// deep. One sparse backward analysis over the whole module carries, for
// each, where the uses it reaches may take it: out of the frame, into a
// tail call that ends the frame, or round a loop that builds the next
// iteration's cell in the same slot. A parameter's own state is its
// summary over the module's calls, as the least solution, so a parameter
// a function only passes to itself does not escape through that call.
#ifndef IDR_ANALYSIS_ESCAPES_H
#define IDR_ANALYSIS_ESCAPES_H

#include "idr/IR/IdrDialect.h"

#include "mlir/Analysis/DataFlowFramework.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Pass/AnalysisManager.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"

namespace idr {

class Escapes {
public:
  // Finds the cycles of calls of `module`, then solves the escapes of every
  // value of its functions at once.
  Escapes(mlir::Operation *module, mlir::AnalysisManager &am);
  bool isInvalidated(const mlir::AnalysisManager::PreservedAnalyses &pa) const;

  // Whether the solve reached its fixpoint; no answer below holds if not.
  mlir::LogicalResult solved() const { return status; }

  // Whether the cell that `con`, a box's constructor, builds may outlive
  // its frame, or be live when `con` runs again in the same frame.
  bool mayEscape(ConOp con) const;

  // Whether `fn` is on a cycle of calls, so that it may have more than one
  // frame live at a time. A function's call of itself in tail position does
  // not count: idr-tail-loops makes it the next iteration of a loop in the
  // same frame. A function on no cycle has at most one frame on the stack
  // at a time.
  bool recursive(FuncOp fn) const;

private:
  // The cycles of calls among the module's functions: a call names its
  // callee. Each function's component, and the functions on a cycle.
  void findCycles(mlir::ModuleOp module, mlir::SymbolTable &symbols);

  mlir::Operation *module;
  llvm::DenseMap<mlir::Operation *, unsigned> component;
  llvm::DenseSet<mlir::Operation *> onCycle;
  // The collection the backward base is built with. idr.call reaches the
  // base never, so it stays empty.
  mlir::SymbolTableCollection unresolved;
  mlir::DataFlowSolver solver;
  mlir::LogicalResult status = mlir::failure();
};

} // namespace idr

#endif // IDR_ANALYSIS_ESCAPES_H
