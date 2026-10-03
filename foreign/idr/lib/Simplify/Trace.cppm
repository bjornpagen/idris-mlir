// idr.simplify:trace: the remark after a round of the simplify loop.
export module idr.simplify:trace;

import idr.mlir;

using namespace mlir;

namespace idr::simplify {

// The remark after round `n`: what the module holds, and how long the
// round took.
export void trace(ModuleOp module, unsigned n, std::chrono::steady_clock::duration took) {
  remark::detail::InFlightRemark out = remark::analysis(
      module.getLoc(), remark::RemarkOpts::name("round").category("idr-simplify"));
  // The walk costs as much as the module is large: only for a remark
  // someone reads.
  if (!out)
    return;
  unsigned functions = 0, clones = 0;
  for (auto fn : module.getOps<func::FuncOp>()) {
    ++functions;
    if (fn->hasAttr("idr.clone"))
      ++clones;
  }
  uint64_t ops = 0;
  module.walk([&](Operation *) { ++ops; });
  double ms = std::chrono::duration<double, std::milli>(took).count();
  out << remark::metric("round", n) << remark::metric("functions", functions)
      << remark::metric("clones", clones) << remark::metric("ops", ops)
      << remark::metric("ms", llvm::formatv("{0:f3}", ms).str());
}

} // namespace idr::simplify
