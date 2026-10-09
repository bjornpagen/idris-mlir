// idr.support:statistics: the statistics of the passes a pass runs itself
// (Pass::runPipeline). The pass manager prints the statistics of the passes
// it runs, never those of such a pipeline, so the owner shows them as its
// own: one statistic per statistic of the pipeline's passes, named
// `<pass argument>.<name>` and summed over the passes of one argument.
module;
// LLVM_ENABLE_STATS, a macro, which no import carries.
#include "llvm/ADT/Statistic.h"

export module idr.support:statistics;

import idr.mlir;

export namespace idr::support {

class PipelineStatistics {
public:
  PipelineStatistics() = default;
  // The statistics belong to one owner: a copy of the owner (the pass
  // manager clones passes) declares its own.
  PipelineStatistics(const PipelineStatistics &);
  PipelineStatistics &operator=(const PipelineStatistics &) = delete;

  // Gives the owner one statistic per name among `pipeline`'s passes, each
  // the sum of its sources there. Declared as soon as the pipeline is
  // built, before it runs, every instance of the owner lists the same
  // statistics, as the pass manager's merged list expects; a pipeline built
  // again takes the place of the old one.
  void declare(mlir::Pass &owner, mlir::OpPassManager &pipeline);

  // Sets each statistic to the sum of its sources so far.
  void fold();

  // The statistics, as metrics of `remark`.
  void addMetrics(mlir::remark::detail::InFlightRemark &remark) const;

private:
  struct Entry {
    Entry(mlir::Pass &owner, std::string key, std::string text);
    // The statistic points into these.
    std::string name, description;
    mlir::Pass::Statistic statistic;
    llvm::SmallVector<const mlir::Pass::Statistic *> sources;
  };
  // In the order the pipeline first shows each name.
  std::vector<std::unique_ptr<Entry>> entries;
  llvm::StringMap<Entry *> byName;
};

} // namespace idr::support

using namespace mlir;

// A pass statistic must have the layout the MLIR library gives it, which
// holds the count: the pinned LLVM is built with LLVM_FORCE_ENABLE_STATS,
// so its llvm-config.h says statistics count in our Release build too.
static_assert(LLVM_ENABLE_STATS, "pass statistics need an LLVM built with LLVM_FORCE_ENABLE_STATS");

idr::support::PipelineStatistics::PipelineStatistics(const PipelineStatistics &) {}

idr::support::PipelineStatistics::Entry::Entry(Pass &owner, std::string key, std::string text)
    : name(std::move(key)), description(std::move(text)),
      statistic(&owner, name.c_str(), description.c_str()) {}

void idr::support::PipelineStatistics::declare(Pass &owner, OpPassManager &pipeline) {
  for (const std::unique_ptr<Entry> &entry : entries)
    entry->sources.clear();
  for (Pass &pass : pipeline.getPasses())
    for (const Pass::Statistic *source : pass.getStatistics()) {
      std::string name = (pass.getArgument() + "." + source->getName()).str();
      Entry *&entry = byName[name];
      if (!entry)
        entry = entries.emplace_back(std::make_unique<Entry>(owner, name, source->getDesc())).get();
      entry->sources.push_back(source);
    }
}

void idr::support::PipelineStatistics::fold() {
  for (const std::unique_ptr<Entry> &entry : entries) {
    uint64_t total = 0;
    for (const Pass::Statistic *source : entry->sources)
      total += source->getValue();
    // Pass::Statistic assigns only an unsigned.
    llvm::Statistic &value = entry->statistic;
    value = total;
  }
}

void idr::support::PipelineStatistics::addMetrics(remark::detail::InFlightRemark &remark) const {
  for (const std::unique_ptr<Entry> &entry : entries)
    remark << remark::metric(entry->name, entry->statistic.getValue());
}
