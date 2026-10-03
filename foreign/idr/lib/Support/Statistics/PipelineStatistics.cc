// The statistics of the passes a pass runs itself.
module;
// LLVM_ENABLE_STATS, a macro, which no import carries.
#include "llvm/ADT/Statistic.h"

module idr.support;

import idr.mlir;

using namespace mlir;

// PIN(llvm-force-enable-stats): a pass statistic must have the layout the
// MLIR library gives it, which holds the count.
static_assert(LLVM_ENABLE_STATS, "pass statistics need LLVM_FORCE_ENABLE_STATS (PINS.md)");

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
