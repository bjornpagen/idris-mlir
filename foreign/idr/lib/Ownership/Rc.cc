// idr-rc: every reference made explicit, in Lean's order: reset/reuse
// insertion, borrow inference, then the incs and decs. The module is then
// in the owned stage, which the verifier checks after every later pass.

#include "Ownership/Ownership.h"

#include "Lower/Layout.h"

using namespace mlir;

namespace idr {
#define GEN_PASS_DEF_IDRRC
#include "idr/Passes.h.inc"
} // namespace idr

namespace {

struct Rc : idr::impl::IdrRcBase<Rc> {
  using IdrRcBase::IdrRcBase;

  void runOnOperation() override {
    ModuleOp module = getOperation();
    namespace own = idr::ownership;
    if (module->hasAttr(own::stageAttr)) {
      module.emitError("idr-rc: the module is already in the owned stage");
      return signalPassFailure();
    }
    own::Counting counting(module);
    SmallVector<func::FuncOp> functions;
    for (auto fn : module.getOps<func::FuncOp>())
      if (!fn.isExternal())
        functions.push_back(fn);
    if (reuse) {
      FailureOr<idr::lower::Layouts> layouts = idr::lower::Layouts::of(module);
      if (failed(layouts))
        return signalPassFailure();
      for (func::FuncOp fn : functions) {
        auto [resets, reuses] = own::insertResetReuse(fn, *layouts);
        numResets += resets;
        numReuses += reuses;
      }
    }
    if (borrow)
      numBorrowed += own::inferBorrows(module, counting);
    for (func::FuncOp fn : functions) {
      FailureOr<std::pair<unsigned, unsigned>> counts = own::insertCounts(fn, counting);
      if (failed(counts))
        return signalPassFailure();
      numIncs += counts->first;
      numDecs += counts->second;
    }
    module->setAttr(own::stageAttr, StringAttr::get(&getContext(), own::ownedStage));
  }
};

} // namespace
