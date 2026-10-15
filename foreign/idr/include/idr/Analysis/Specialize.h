// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What specialization decides by: the binding time of every parameter,
// written once per function: for a function the module held, when its
// component of the direct calls is ready, from the component's bodies; for
// a node, when it is built, from its owner's. Read by name, the symbol a
// call's callee gives, from any worker.
#ifndef IDR_ANALYSIS_SPECIALIZE_H
#define IDR_ANALYSIS_SPECIALIZE_H

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/Pass/AnalysisManager.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"

#include <cstdint>
#include <optional>
#include <shared_mutex>

namespace idr {

// The binding time of one parameter: which static arguments a call may
// specialize on there.
enum class BindingTime : uint8_t {
  // The function is on no cycle: a call specializes on anything static.
  Free,
  Fixed,
  Decreasing,
  Bounded,
  Other,
};

// The name idr-binding-times reports a binding time by.
llvm::StringRef nameOf(BindingTime time);

// Which parameters of a function a call may specialize on.
//
// A function is on a cycle when its component of the direct calls has two
// or more functions, or when it calls itself. A parameter of such a
// function is
//   - fixed when every call to the function from its component passes it
//     unchanged in the same position: one specialization serves the whole
//     recursion, whose calls then have its key;
//   - decreasing when every such call passes a proper part of it: a field
//     of it, an argument of a region of a match on it, or its predecessor
//     as a Nat (`idr.big.pred`, defined on non-zero values only); the keys
//     shrink along the chain of specializations;
//   - bounded when every such call passes it or a proper part of it: the
//     keys are parts of the first one;
//   - other otherwise: an accumulator, a counter, a closure rebuilt on
//     every iteration. A call never specializes on it.
//
// The result holds one list per function of `component`, in its order, one
// binding time per parameter. Each body is read as it is now; nothing
// outside `component` is read.
llvm::SmallVector<llvm::SmallVector<BindingTime>>
bindingTimesOf(llvm::ArrayRef<idr::FuncOp> component);

// The binding times of a run of idr-optimize, by function name. Built empty
// by the module's analysis manager.
class BindingTimes {
public:
  BindingTimes(mlir::Operation *module, mlir::AnalysisManager &am);
  ~BindingTimes();
  bool isInvalidated(const mlir::AnalysisManager::PreservedAnalyses &pa) const;

  // Each member of `component` without binding times gets them from
  // bindingTimesOf, over the members that have none. Safe on disjoint
  // components from different workers.
  void solve(llvm::ArrayRef<idr::FuncOp> component);
  // A node's, written once by its build: its owner's, by its key.
  void inherit(mlir::StringAttr fn, llvm::SmallVector<BindingTime> times);

  // None for a function that has none yet, or past its parameters.
  std::optional<BindingTime> of(mlir::StringAttr fn, unsigned index) const;
  llvm::SmallVector<BindingTime> of(mlir::StringAttr fn) const;

private:
  mutable std::shared_mutex mutex;
  llvm::DenseMap<mlir::StringAttr, llvm::SmallVector<BindingTime>> times;
};

} // namespace idr

#endif // IDR_ANALYSIS_SPECIALIZE_H
