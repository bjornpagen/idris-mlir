// The rewrites of a greedy pattern driver, by pattern: a listener
// (GreedyRewriteConfig::setListener) that counts each pattern that applies,
// by its debug name. Folds are no patterns, and are not counted.
#pragma once

#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/Remarks.h"

#include "llvm/ADT/StringMap.h"

#include <cstdint>

namespace idr::support {

class PatternCounts : public mlir::RewriterBase::Listener {
public:
  void notifyPatternEnd(const mlir::Pattern &pattern, llvm::LogicalResult status) override;

  // The rewrites of every pattern.
  uint64_t total() const { return sum; }

  // The rewrites of each pattern that applied, as metrics of `remark`, by
  // pattern name.
  void addMetrics(mlir::remark::detail::InFlightRemark &remark) const;

private:
  llvm::StringMap<uint64_t> counts;
  uint64_t sum = 0;
};

} // namespace idr::support
