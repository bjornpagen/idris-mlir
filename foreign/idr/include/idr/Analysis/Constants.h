// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a call of each function returns, as constant propagation knows it,
// carried across calls bottom-up. Each function is solved on its own, with
// upstream's sparse constant propagation and dead-code analysis and no
// interprocedural mode, and a call's results come from what its callee
// returns, read once the callee's component is final. What a caller passes
// is not carried down: specialization is how a static argument reaches a
// callee.
#ifndef IDR_ANALYSIS_CONSTANTS_H
#define IDR_ANALYSIS_CONSTANTS_H

#include "idr/IR/IdrDialect.h"

#include "mlir/Analysis/DataFlow/ConstantPropagationAnalysis.h"
#include "mlir/IR/Operation.h"
#include "mlir/Support/TypeID.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <concepts>
#include <utility>

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

// The results of a call as its caller may read them: its callee's
// returnedConstants once the callee's component is final, and unknown at
// every result before, so that a call within a component assumes nothing of
// its callee and no answer depends on the order in which a component's
// members ran. Unknown is what upstream's entry state joins.
template <class R>
concept CalleeReturns = requires(const R &read, idr::CallOp call) {
  { read(call) } -> std::same_as<ConstantResults>;
};

// Upstream's sparse constant propagation on one function, with a call's
// results taken from its callee's summary: the hook upstream gives a solve
// that does not enter callees. `read` outlives the solver. One type per
// reader, each with its own identity in the solver.
template <CalleeReturns R>
class SummarizedConstantPropagation : public mlir::dataflow::SparseConstantPropagation {
public:
  static mlir::TypeID resolveTypeID() {
    static mlir::SelfOwningTypeID id;
    return id;
  }

  SummarizedConstantPropagation(mlir::DataFlowSolver &solver, const R &read)
      : SparseConstantPropagation(solver), read(read) {}

  // A program at the stage the optimizer runs holds no call but idr.call.
  void visitExternalCall(
      mlir::CallOpInterface call,
      llvm::ArrayRef<const mlir::dataflow::Lattice<mlir::dataflow::ConstantValue> *>,
      llvm::ArrayRef<mlir::dataflow::Lattice<mlir::dataflow::ConstantValue> *> results) override {
    ConstantResults returned = read(mlir::cast<idr::CallOp>(call.getOperation()));
    for (auto [lattice, value] : llvm::zip_equal(results, returned))
      propagateIfChanged(lattice, lattice->join(value));
  }

private:
  const R &read;
};

} // namespace idr

#endif // IDR_ANALYSIS_CONSTANTS_H
