// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Which cells may outlive the frame that makes them, and which functions
// may have more than one frame live at a time: what idr-rc's stack step
// decides by.
//
// The address of a cell is held by SSA values and parameters: the cell
// itself, whose fields are not yet written, and the box idr.cell.init makes
// of it; and by the fields of other cells and of unboxed sums. Each value
// that may hold one stands in two ways: for the address it holds of its own
// (shallow), and for everything reachable from it through fields, its own
// too (deep). An unboxed sum has no address of its own, so it stands only
// deep. One sparse backward analysis over the whole program carries, for
// each, where the uses it reaches may take it: out of the frame, into a
// tail call that ends the frame, or round a loop that makes the next
// iteration's cell in the same slot. No call is entered: a parameter's own
// state is its summary over the program's calls, as the least solution, so
// a parameter a function only passes to itself does not escape through that
// call. What each use does with a value is what its op's flow says of the
// references it moves (idr/IR/Flow.h), except where the op's result is its
// operand's value: there the address goes on whole, whatever the op does
// with the reference.
#ifndef IDR_ANALYSIS_ESCAPES_H
#define IDR_ANALYSIS_ESCAPES_H

#include "idr/Analysis/CallCycles.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/Analysis/DataFlowFramework.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Pass/AnalysisManager.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/SmallVector.h"

#include <optional>

namespace idr {

class Escapes {
public:
  // Reads the cycles of calls of `program`, an idr.program, then solves the
  // escapes of every value of its functions at once. The solve runs until
  // its worklist is empty, which a lattice of finite height over the
  // program's values guarantees, and no visit of it fails.
  Escapes(mlir::Operation *program, mlir::AnalysisManager &am);
  bool isInvalidated(const mlir::AnalysisManager::PreservedAnalyses &pa) const;

  // Whether the cell `cell` makes may outlive its frame, or be live when
  // `cell` runs again in the same frame.
  bool mayEscape(CellNewOp cell) const;

  // Whether `fn` is on a cycle of calls, so that it may have more than one
  // frame live at a time. A function's call of itself in tail position does
  // not count: idr-tail-loops makes it the next iteration of a loop in the
  // same frame. A function on no cycle has at most one frame on the stack
  // at a time.
  bool recursive(FuncOp fn) const;

private:
  // The functions on a cycle, from the program's cycles of calls.
  void findCycles(const CallCycles &cycles);

  // The loops around `op`, a cell op, innermost first: the region branches
  // whose region holding it runs again, and may run it again in its frame,
  // writing its slot again. Nothing when it is anywhere else than in
  // regions of one block each of region branches whose runs never overlap,
  // in the body of a function of the program, one block by its type.
  std::optional<llvm::SmallVector<mlir::Operation *, 2>> loopsAround(mlir::Operation *op) const;

  mlir::Operation *program;
  llvm::DenseSet<mlir::Operation *> onCycle;
  // The table every call's callee is found through: the backward base
  // resolves a call by it before it hands the call to the solve's hook,
  // which reads the callee's parameters.
  mlir::SymbolTableCollection tables;
  // The solve enters no callee: the base hands every call to the hook,
  // whose rule is the callee's summaries.
  mlir::DataFlowSolver solver{mlir::DataFlowConfig().setInterprocedural(false)};
};

} // namespace idr

#endif // IDR_ANALYSIS_ESCAPES_H
