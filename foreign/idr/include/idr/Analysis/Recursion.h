// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Which functions may have more than one frame live at a time, read off
// the program's cycles of calls: what idr-rc's stack step budgets a frame
// by. A function's call of itself in tail position does not count:
// idr-tail-loops makes it the next iteration of a loop in the same frame.
// A function on no cycle has at most one frame on the stack at a time.
#ifndef IDR_ANALYSIS_RECURSION_H
#define IDR_ANALYSIS_RECURSION_H

#include "idr/Analysis/CallCycles.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/Pass/AnalysisManager.h"
#include "llvm/ADT/DenseSet.h"

namespace idr {

class Recursion {
public:
  // Reads the cycles of calls of `program`, an idr.program.
  Recursion(mlir::Operation *program, mlir::AnalysisManager &am);
  bool isInvalidated(const mlir::AnalysisManager::PreservedAnalyses &pa) const;

  // Whether `fn` is on a cycle of calls, so that it may have more than one
  // frame live at a time.
  bool recursive(FuncOp fn) const { return onCycle.contains(fn.getOperation()); }

private:
  llvm::DenseSet<mlir::Operation *> onCycle;
};

} // namespace idr

#endif // IDR_ANALYSIS_RECURSION_H
