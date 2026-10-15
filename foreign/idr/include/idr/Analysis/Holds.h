// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Whether a value of a type may hold a world, as an analysis the passes
// that ask it take from the analysis manager. The answer is the type's own
// (idr::holdsWorld), kept by each data type with its body, so this holds
// nothing, is never stale, and may be asked from any thread.
#ifndef IDR_ANALYSIS_HOLDS_H
#define IDR_ANALYSIS_HOLDS_H

#include "idr/IR/IdrDialect.h"

#include "mlir/Pass/AnalysisManager.h"

namespace idr {

class Holds {
public:
  Holds(mlir::Operation *module, mlir::AnalysisManager &am);

  // The answers are the types', which a pass that changes a type changes
  // with it.
  bool isInvalidated(const mlir::AnalysisManager::PreservedAnalyses &) const { return false; }

  // Whether a value of `type` may hold a world: a world, or a value that
  // holds one in place, in a box or in an array's elements. A closure never
  // captures one, so a world reaches a function only through its
  // parameters.
  bool mayHoldWorld(mlir::Type type) const { return holdsWorld(type); }
};

} // namespace idr

#endif // IDR_ANALYSIS_HOLDS_H
