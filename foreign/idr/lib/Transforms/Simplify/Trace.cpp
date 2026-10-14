// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What idr-simplify reports as it runs: the census of the module
// after a round, the remark that carries it, and the statistics of
// the round's passes, which -mlir-pass-statistics never prints (the
// passes run in the composite's pipeline, not the manager's).

#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Simplify.h"

#include "mlir/IR/Remarks.h"

#include "llvm/Support/FormatVariadic.h"

using namespace mlir;

idr::SimplifyCensus idr::takeSimplifyCensus(ModuleOp module) {
  SimplifyCensus census;
  for (idr::FuncOp fn : module.getOps<idr::FuncOp>()) {
    ++census.functions;
    if (fn.getClone())
      ++census.clones;
  }
  module.walk([&](Operation *) { ++census.ops; });
  return census;
}

void idr::traceSimplifyRound(ModuleOp module, unsigned round,
                             std::chrono::steady_clock::duration took,
                             llvm::function_ref<const SimplifyCensus &()> census) {
  remark::detail::InFlightRemark out = remark::analysis(
      module.getLoc(), remark::RemarkOpts::name("round").category("idr-simplify"));
  // The census walks the module: only for a remark someone reads.
  if (!out)
    return;
  const SimplifyCensus &counts = census();
  double ms = std::chrono::duration<double, std::milli>(took).count();
  out << remark::metric("round", round) << remark::metric("functions", counts.functions)
      << remark::metric("clones", counts.clones) << remark::metric("ops", counts.ops)
      << remark::metric("ms", llvm::formatv("{0:f3}", ms).str());
}

void idr::reportSimplifyStatistics(ModuleOp module,
                                   const std::map<std::string, uint64_t> &totals) {
  if (remark::detail::InFlightRemark out = remark::analysis(
          module.getLoc(), remark::RemarkOpts::name("statistics").category("idr-simplify")))
    for (const auto &[name, total] : totals)
      out << remark::metric(name, total);
}
