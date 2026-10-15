// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a value of a type may hold: a world, or a closure, through the
// fields of the data it is. Two bits per data type, computed for every data
// type at once in the constructor and never changed afterwards, so function
// passes may ask from any thread; idr-optimize takes it before its first
// task and reads it frozen.
#ifndef IDR_ANALYSIS_HOLDS_H
#define IDR_ANALYSIS_HOLDS_H

#include "idr/IR/IdrDialect.h"

#include "mlir/Pass/AnalysisManager.h"
#include "llvm/ADT/DenseMap.h"

#include <cstdint>

namespace idr {

class Holds {
public:
  Holds(mlir::Operation *module, mlir::AnalysisManager &am);

  // Unless it and the TypeGraph it was computed from are preserved.
  bool isInvalidated(const mlir::AnalysisManager::PreservedAnalyses &pa) const;

  // Whether a value of `type` may hold a world: a world, or data with a
  // field that may. A closure never captures one, so a world reaches a
  // function only through its parameters.
  bool mayHoldWorld(mlir::Type type) const;
  // Whether a value of `type` may hold a closure: a closure, a sum of
  // closures that idr-defunctionalize made, or data with a field that may.
  bool mayHoldClosure(mlir::Type type) const;

private:
  uint8_t bitsOf(mlir::Type type) const;

  // By data type, which a value's type names through its box and grade.
  llvm::DenseMap<mlir::Type, uint8_t> bits;
};

} // namespace idr

#endif // IDR_ANALYSIS_HOLDS_H
