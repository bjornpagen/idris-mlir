// idr.support:counts: the rewrites of a greedy pattern driver, by pattern:
// a listener (GreedyRewriteConfig::setListener) that counts each pattern
// that applies, by its debug name. Folds are no patterns, and are not
// counted.
export module idr.support:counts;

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

export namespace idr::support {

class PatternCounts : public mlir::RewriterBase::Listener {
public:
  void notifyPatternEnd(const mlir::Pattern &pattern, llvm::LogicalResult status) override {
    if (failed(status))
      return;
    ++sum;
    ++counts[nameOf(pattern)];
  }

  // The rewrites of every pattern.
  uint64_t total() const { return sum; }

  // The rewrites of each pattern that applied, as metrics of `remark`, by
  // pattern name.
  void addMetrics(mlir::remark::detail::InFlightRemark &remark) const {
    llvm::SmallVector<llvm::StringRef> names;
    for (const auto &count : counts)
      names.push_back(count.getKey());
    llvm::sort(names);
    for (llvm::StringRef name : names)
      remark << remark::metric(name, counts.lookup(name));
  }

private:
  llvm::StringMap<uint64_t> counts;
  uint64_t sum = 0;
};

} // namespace idr::support
