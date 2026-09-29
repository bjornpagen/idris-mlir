#include "Support/PatternCounts.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <optional>
#include <string>

using namespace mlir;

// A pattern made from a function has no debug name: it goes by the op it
// matches.
static std::string nameOf(const Pattern &pattern) {
  if (!pattern.getDebugName().empty())
    return pattern.getDebugName().str();
  std::optional<OperationName> root = pattern.getRootKind();
  return root ? ("(" + root->getStringRef() + ")").str() : "(any op)";
}

void idr::support::PatternCounts::notifyPatternEnd(const Pattern &pattern,
                                                   llvm::LogicalResult status) {
  if (failed(status))
    return;
  ++sum;
  ++counts[nameOf(pattern)];
}

void idr::support::PatternCounts::addMetrics(remark::detail::InFlightRemark &remark) const {
  llvm::SmallVector<llvm::StringRef> names;
  for (const auto &count : counts)
    names.push_back(count.getKey());
  llvm::sort(names);
  for (llvm::StringRef name : names)
    remark << remark::metric(name, counts.lookup(name));
}
