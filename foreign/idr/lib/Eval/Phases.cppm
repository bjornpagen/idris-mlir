// idr.eval:phases: the time a run of idr-eval spends on each phase of a
// round. Nothing here is exported.
export module idr.eval:phases;

import idr.mlir;

using namespace mlir;

namespace idr::eval {

// What one run of the pass spends on each phase of evaluating its fresh
// calls, as the remark `round` of the category idr-eval reports it: the
// pass manager's timing (-mlir-timing) sees the lowering pipelines it runs,
// but not the JIT or the child.
struct Phases {
  using Clock = std::chrono::steady_clock;
  Clock::time_point mark = Clock::now();
  double prepare = 0, lower = 0, convert = 0, jit = 0, run = 0, decode = 0;

  // Adds the time since the last mark to `phase`, and marks now.
  void lap(double &phase) {
    Clock::time_point now = Clock::now();
    phase += std::chrono::duration<double, std::milli>(now - mark).count();
    mark = now;
  }

  void report(Location loc, size_t calls) const {
    remark::detail::InFlightRemark out =
        remark::analysis(loc, remark::RemarkOpts::name("round").category("idr-eval"));
    if (!out)
      return;
    auto ms = [](double value) { return llvm::formatv("{0:f3}", value).str(); };
    out << remark::metric("calls", calls) << remark::metric("prepare-ms", ms(prepare))
        << remark::metric("lower-ms", ms(lower)) << remark::metric("convert-ms", ms(convert))
        << remark::metric("jit-ms", ms(jit)) << remark::metric("run-ms", ms(run))
        << remark::metric("decode-ms", ms(decode));
  }
};

} // namespace idr::eval
