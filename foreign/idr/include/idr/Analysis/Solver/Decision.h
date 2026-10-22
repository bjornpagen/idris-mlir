// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// How a whole-program fact reaches the function passes the pass manager
// runs in parallel: decide, apply, restructure.
//
// A decide step is a pass on idr.program that changes no op: it computes
// one decision analysis, and makes, serially and in id order, every type
// and attribute its answer needs, so no worker of the apply step creates
// anything in the context. It preserves everything, so the verifier skips
// it.
//
// An apply step is a nested group of function passes. Each function reads
// the decision through a const reference and rewrites itself whole; it
// reads no sibling. The pipeline's record pairs each apply step with its
// decide step, so a missing decision is an internal error, never a state
// to recover from.
//
// A restructure step is a pass on idr.program that adds, erases or
// redirects functions, editing the program graph through its editor.
#ifndef IDR_ANALYSIS_SOLVER_DECISION_H
#define IDR_ANALYSIS_SOLVER_DECISION_H

#include "mlir/Pass/AnalysisManager.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/ADT/Twine.h"
#include "llvm/Support/ErrorHandling.h"

#include <concepts>
#include <functional>
#include <optional>
#include <tuple>

namespace idr::solver {

// A decision analysis names the decide step that makes it.
template <class D>
concept DecisionAnalysis = requires {
  { D::decideStep } -> std::convertible_to<llvm::StringLiteral>;
};

// What an apply step reads: the program's cached decision, as
// Pass::getCachedParentAnalysis returns it, through a const reference.
template <DecisionAnalysis D>
const D &decided(std::optional<std::reference_wrapper<D>> cached) {
  if (!cached)
    llvm::reportFatalInternalError(llvm::Twine("an apply step ran before its decide step, ") +
                                   D::decideStep);
  return cached->get();
}

// An analysis that reads other analyses names them in its type: it fetches
// them as const references through `reads`, and is invalidated whenever
// one of them is, so its invalidation cannot drift from what it reads.
template <class Self, class... Read>
class ReadsAnalyses {
public:
  bool isInvalidated(const mlir::AnalysisManager::PreservedAnalyses &pa) const {
    return !pa.isPreserved<Self>() || (!pa.isPreserved<Read>() || ...);
  }

protected:
  static std::tuple<const Read &...> reads(mlir::AnalysisManager &am) {
    return std::tuple<const Read &...>(am.getAnalysis<Read>()...);
  }
};

} // namespace idr::solver

#endif // IDR_ANALYSIS_SOLVER_DECISION_H
