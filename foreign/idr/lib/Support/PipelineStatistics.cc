#include "Support/PipelineStatistics.h"

#include "llvm/ADT/Statistic.h"

using namespace mlir;

// PIN(llvm-force-enable-stats): a pass statistic must have the layout the
// MLIR library gives it, which holds the count.
static_assert(LLVM_ENABLE_STATS, "pass statistics need LLVM_FORCE_ENABLE_STATS (PINS.md)");

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
