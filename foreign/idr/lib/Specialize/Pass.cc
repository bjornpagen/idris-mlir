// idr-specialize, and idr-binding-times, which reports what it decides on.

#include "idr/Idr.h"

namespace idr {
#define GEN_PASS_DEF_IDRSPECIALIZE
#define GEN_PASS_DEF_IDRBINDINGTIMES
#include "idr/Passes.h.inc"
} // namespace idr

import idr.specialize;

using namespace mlir;
using namespace idr::specialize;

namespace {

struct Specialize : idr::impl::IdrSpecializeBase<Specialize> {
  void runOnOperation() override {
    ModuleOp module = getOperation();
    // A redirect onto a clone made in an earlier run rewrites a call and
    // is not one of the statistics. The fingerprint is the rewrite.
    OperationFingerPrint before(module);
    Specializer specializer(module);
    LogicalResult result = specializer.run();
    const Statistics &stats = specializer.stats;
    numClones += stats.clones;
    numRaised += stats.raised;
    numShared += stats.shared;
    numFree += stats.free;
    numFixed += stats.fixed;
    numDecreasing += stats.decreasing;
    numBounded += stats.bounded;
    if (failed(result))
      return signalPassFailure();
    // The run rewrote nothing. Preserving every analysis skips the walk of
    // every nested operation.
    if (before == OperationFingerPrint(module))
      markAllAnalysesPreserved();
  }
};

struct ReportBindingTimes : idr::impl::IdrBindingTimesBase<ReportBindingTimes> {
  void runOnOperation() override {
    ModuleOp module = getOperation();
    CloneTable clones(module);
    BindingTimes times(module, clones);
    for (auto fn : module.getOps<func::FuncOp>()) {
      if (fn.isExternal())
        continue;
      InFlightDiagnostic remark = fn.emitRemark() << "@" << fn.getSymName() << ":";
      for (unsigned i = 0; i < fn.getNumArguments(); ++i)
        remark << (i ? ", " : " ") << nameOf(*times.of(fn, i));
    }
  }
};

} // namespace
