// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The ranges of the program's integers, bigs and naturals, as MLIR's
// integer range analysis finds them across calls, a natural it cannot see
// computed starting at 0. idr-narrow reads it; nothing else solves it.
#ifndef IDR_ANALYSIS_RANGES_H
#define IDR_ANALYSIS_RANGES_H

#include "idr/IR/IdrDialect.h"

#include "mlir/Analysis/DataFlowFramework.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/Value.h"
#include "mlir/Interfaces/InferIntRangeInterface.h"

#include <memory>
#include <optional>

namespace idr {

// One interprocedural solve of the program, which exists only once MLIR's
// solver reached its fixpoint: a solve that did not proves nothing, and is
// no Ranges. It holds no IR beyond the pass that solved it; while it
// lives, several function passes may read it at once, and none writes it.
class Ranges {
public:
  // The solve of `program`; failure when the solver fails, an internal
  // error the caller reports. MLIR's analysis widens a value's range to any
  // value once a merge has changed it 128 times, as a loop-carried counter
  // would by one per visit; a big's or a natural's becomes the range of no
  // width, which states no bounds. That widening is what ends the solve on
  // such a counter, and it only loses precision: a wider range is still a
  // range of the value, and every reader takes a range as a bound to
  // narrow or version under, leaving the value wide where it states none.
  // Nothing refuses or errors on a range; a solve fails only when an
  // analysis fails to visit an op, which no join causes.
  static mlir::FailureOr<std::unique_ptr<const Ranges>> solve(ProgramOp program);

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
  Ranges();

  // The analyses the solver holds refer to it, so it stays where it was
  // made.
  mlir::DataFlowSolver dataflow;
};

} // namespace idr

#endif // IDR_ANALYSIS_RANGES_H
