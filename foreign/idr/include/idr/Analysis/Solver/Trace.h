// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A solve unit (one function's or one component's part of a solve) is a
// trace zone, never an action. An action's handler decides whether its
// unit runs, and a debug counter may skip it: a skipped unit of a marking
// whose start is the optimistic bottom leaves an unsound answer, and a
// skipped unit of a refusal analysis moves acceptance, as a budget of zero
// would. A transform, whose skip leaves valid IR, is an action
// (support::perform); a solve unit is this, a different type, so it cannot
// be written as one.
#ifndef IDR_ANALYSIS_SOLVER_TRACE_H
#define IDR_ANALYSIS_SOLVER_TRACE_H

#include "llvm/ADT/StringRef.h"
#include "llvm/Support/TimeProfiler.h"

namespace idr::solver {

class SolveUnit {
public:
  // A zone named by its analysis, its detail the unit's function.
  SolveUnit(llvm::StringLiteral analysis, llvm::StringRef unit) : zone(analysis, unit) {}
  SolveUnit(const SolveUnit &) = delete;
  SolveUnit &operator=(const SolveUnit &) = delete;

private:
  llvm::TimeTraceScope zone;
};

} // namespace idr::solver

#endif // IDR_ANALYSIS_SOLVER_TRACE_H
