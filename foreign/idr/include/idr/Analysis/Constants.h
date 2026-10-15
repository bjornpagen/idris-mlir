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
#include "llvm/ADT/STLFunctionalExtras.h"
#include "llvm/ADT/SmallVector.h"

namespace idr {

// What a call of a function returns, one lattice value per result:
// uninitialized where the function has no return, a constant, or unknown.
using ConstantResults = llvm::SmallVector<mlir::dataflow::ConstantValue, 1>;

// What `fn` returns, read from its final body: idr-constants ran last on
// it and replaced every value its solve held constant, so a return's
// operand is a constant exactly where the solve found one. The body is the
// fact; nothing holds a copy of the solve between the function's last step
// and its component's end.
ConstantResults returnedConstants(idr::FuncOp fn);

// The results of the function named `callee` as its callers may read them:
// null while its component is not final, so that a call within a component
// assumes nothing of its callee and no answer depends on the order in which
// a component's members ran.
using ConstantsOf = llvm::function_ref<const ConstantResults *(mlir::StringAttr callee)>;

// Upstream's sparse constant propagation on one function, with a call's
// results taken from its callee's summary: the hook upstream gives a solve
// that does not enter callees. `constantsOf` outlives the solver.
class SummarizedConstantPropagation : public mlir::dataflow::SparseConstantPropagation {
public:
  SummarizedConstantPropagation(mlir::DataFlowSolver &solver, ConstantsOf constantsOf);

  void visitExternalCall(
      mlir::CallOpInterface call,
      llvm::ArrayRef<const mlir::dataflow::Lattice<mlir::dataflow::ConstantValue> *> arguments,
      llvm::ArrayRef<mlir::dataflow::Lattice<mlir::dataflow::ConstantValue> *> results) override;

private:
  ConstantsOf constantsOf;
};

} // namespace idr

#endif // IDR_ANALYSIS_CONSTANTS_H
