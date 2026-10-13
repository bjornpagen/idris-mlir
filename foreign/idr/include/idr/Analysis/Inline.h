// Which functions idr-inline inlines, decided from the references among
// functions before anything is inlined.
#ifndef IDR_ANALYSIS_INLINE_H
#define IDR_ANALYSIS_INLINE_H

#include "mlir/IR/Operation.h"
#include "mlir/Pass/AnalysisManager.h"
#include "llvm/ADT/DenseSet.h"

namespace idr {

// The rule, its three numbers and why are with its definition. The
// decisions read References alone, so they stand exactly as long as it does.
class InlineDecisions {
public:
  InlineDecisions(mlir::Operation *module, mlir::AnalysisManager &am);
  bool isInvalidated(const mlir::AnalysisManager::PreservedAnalyses &pa) const;
  // The idr.func the rule lets the inliner inline.
  const llvm::DenseSet<mlir::Operation *> &inlined() const { return chosen; }
  unsigned inlinable() const { return static_cast<unsigned>(chosen.size()); }
  // Of those, how many the leaf rule took.
  unsigned leaves() const { return leafCount; }
  // The idr.call sites whose callee is inlined.
  unsigned inlinableCalls() const { return callCount; }

private:
  llvm::DenseSet<mlir::Operation *> chosen;
  unsigned leafCount = 0;
  unsigned callCount = 0;
};

} // namespace idr

#endif // IDR_ANALYSIS_INLINE_H
