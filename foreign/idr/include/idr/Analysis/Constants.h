// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a call of each function returns, as constant propagation knows it,
// carried across calls bottom-up. Each function is solved on its own, with
// upstream's sparse constant propagation and dead-code analysis and no
// interprocedural mode, and a call's results come from what its callee
// returns, read once the callee's component of the ready set is final. What
// a caller passes is not carried down: specialization is how a static
// argument reaches a callee.
#ifndef IDR_ANALYSIS_CONSTANTS_H
#define IDR_ANALYSIS_CONSTANTS_H

#include "idr/IR/IdrDialect.h"

#include "mlir/Analysis/DataFlow/ConstantPropagationAnalysis.h"
#include "mlir/IR/Operation.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SmallVector.h"

#include <optional>
#include <shared_mutex>

namespace idr {

// What a call of a function returns, one lattice value per result:
// uninitialized where the function has no return, a constant, or unknown.
using ConstantResults = llvm::SmallVector<mlir::dataflow::ConstantValue, 1>;

// The constants summaries of one run of the ready set, built empty by the
// module's analysis manager. The ready set publishes a component's when the
// component is final; idr-constants reads them from any thread. A function
// is never read before its component is published, so a call within a
// component assumes nothing of its callee and no answer depends on the
// order in which a component's members ran.
class ConstantSummaries {
public:
  explicit ConstantSummaries(mlir::Operation *module);

  // The published results of the function named `callee`, or none while
  // its component is not final.
  std::optional<ConstantResults> lookup(mlir::StringAttr callee) const;

  // When every member of `component` is final: what each returns, read from
  // its final body, published for its callers. idr-constants ran last on
  // each body and replaced every operand its solve held constant, so a
  // return's operand is a constant exactly where the solve found one.
  void publish(llvm::ArrayRef<idr::FuncOp> component);

private:
  mutable std::shared_mutex mutex;
  llvm::DenseMap<mlir::StringAttr, ConstantResults> published;
};

// Upstream's sparse constant propagation on one function, with a call's
// results taken from its callee's published summary: the hook upstream
// gives a solve that does not enter callees.
class SummarizedConstantPropagation : public mlir::dataflow::SparseConstantPropagation {
public:
  SummarizedConstantPropagation(mlir::DataFlowSolver &solver, const ConstantSummaries &summaries);

  void visitExternalCall(
      mlir::CallOpInterface call,
      llvm::ArrayRef<const mlir::dataflow::Lattice<mlir::dataflow::ConstantValue> *> arguments,
      llvm::ArrayRef<mlir::dataflow::Lattice<mlir::dataflow::ConstantValue> *> results) override;

private:
  const ConstantSummaries &summaries;
};

} // namespace idr

#endif // IDR_ANALYSIS_CONSTANTS_H
