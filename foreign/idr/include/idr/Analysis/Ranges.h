// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The ranges of the program's integers, bigs and naturals, as MLIR's
// integer range analysis finds them across calls, a natural it cannot see
// computed starting at 0. idr-narrow reads it; nothing else solves it.
#ifndef IDR_ANALYSIS_RANGES_H
#define IDR_ANALYSIS_RANGES_H

#include "mlir/Analysis/DataFlowFramework.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/Value.h"
#include "mlir/Interfaces/InferIntRangeInterface.h"
#include "mlir/Pass/AnalysisManager.h"

#include <optional>

namespace idr {

// One interprocedural solve of the program, kept for the passes that read
// it. It holds no IR beyond the pass that asked for it, since no pass that
// rewrites preserves it; while it lives, several function passes may read
// it at once, and none writes it.
class Ranges {
public:
  explicit Ranges(mlir::Operation *op);

  bool isInvalidated(const mlir::AnalysisManager::PreservedAnalyses &preserved) const {
    return !preserved.isPreserved<Ranges>();
  }

  // Whether the solver ran to its fixpoint; nothing it holds proves
  // anything when it did not.
  bool valid() const { return solved; }

  // Whether counting ran, which the program's stage says: a big taken in
  // place of a word then holds a reference of its own.
  bool counted() const { return owned; }

  // The range found for `value`; none where the analysis never reached it,
  // which proves nothing.
  std::optional<mlir::ConstantIntRanges> rangeOf(mlir::Value value) const {
    return rangeOf(dataflow, value);
  }

  // The one read of an integer range lattice, of this solver or of any
  // other that ran MLIR's integer range analysis.
  static std::optional<mlir::ConstantIntRanges> rangeOf(const mlir::DataFlowSolver &solver,
                                                        mlir::Value value);

private:
  mlir::DataFlowSolver dataflow;
  bool solved = false;
  bool owned = false;
};

} // namespace idr

#endif // IDR_ANALYSIS_RANGES_H
