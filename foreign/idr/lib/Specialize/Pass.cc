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
    Specializer specializer(getOperation());
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
      signalPassFailure();
  }
};

struct ReportBindingTimes : idr::impl::IdrBindingTimesBase<ReportBindingTimes> {
  void runOnOperation() override {
    ModuleOp module = getOperation();
    SymbolTable symbols(module);
    BindingTimes times(module, symbols);
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
