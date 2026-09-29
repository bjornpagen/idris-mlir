// The statistics of the passes a pass runs itself (Pass::runPipeline). The
// pass manager prints the statistics of the passes it runs, never those of
// such a pipeline, so the owner shows them as its own: one statistic per
// statistic of the pipeline's passes, named `<pass argument>.<name>` and
// summed over the passes of one argument.
#pragma once

#include "mlir/IR/Remarks.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Pass/PassManager.h"

#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringMap.h"

#include <memory>
#include <string>
#include <vector>

namespace idr::support {

class PipelineStatistics {
public:
  PipelineStatistics() = default;
  // The statistics belong to one owner: a copy of the owner (the pass
  // manager clones passes) declares its own.
  PipelineStatistics(const PipelineStatistics &) {}
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
    Entry(mlir::Pass &owner, std::string key, std::string text)
        : name(std::move(key)), description(std::move(text)),
          statistic(&owner, name.c_str(), description.c_str()) {}
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
