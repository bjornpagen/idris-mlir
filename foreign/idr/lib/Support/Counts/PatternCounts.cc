// The rewrites of a greedy pattern driver, by pattern.
module idr.support;

import idr.mlir;

using namespace mlir;

namespace {

// A pattern made from a function has no debug name: it goes by the op it
// matches.
std::string nameOf(const Pattern &pattern) {
  if (!pattern.getDebugName().empty())
    return pattern.getDebugName().str();
  std::optional<OperationName> root = pattern.getRootKind();
  return root ? ("(" + root->getStringRef() + ")").str() : "(any op)";
}

} // namespace

void idr::support::PatternCounts::notifyPatternEnd(const Pattern &pattern,
                                                   llvm::LogicalResult status) {
  if (failed(status))
    return;
  ++sum;
  ++counts[nameOf(pattern)];
}

uint64_t idr::support::PatternCounts::total() const { return sum; }

void idr::support::PatternCounts::addMetrics(remark::detail::InFlightRemark &remark) const {
  llvm::SmallVector<llvm::StringRef> names;
  for (const auto &count : counts)
    names.push_back(count.getKey());
  llvm::sort(names);
  for (llvm::StringRef name : names)
    remark << remark::metric(name, counts.lookup(name));
}
