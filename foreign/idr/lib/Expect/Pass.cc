// idr-expect: checks the properties it is given, by name, and changes
// nothing. A request is `name` or `name=argument`; an unknown name is an
// error, so a misspelled property cannot pass.

#include "idr/Idr.h"

#include "mlir/Dialect/MemRef/IR/MemRef.h"

using namespace mlir;

namespace idr {
#define GEN_PASS_DEF_IDREXPECT
#include "idr/Passes.h.inc"
} // namespace idr

import idr.expect;

namespace {

struct Expect : idr::impl::IdrExpectBase<Expect> {
  using IdrExpectBase::IdrExpectBase;

  void runOnOperation() override {
    ModuleOp module = getOperation();
    bool failed = false;
    for (StringRef request : holds) {
      auto [name, argument] = request.split('=');
      idr::expect::Check check = idr::expect::lookup(name);
      if (!check) {
        module.emitError() << "idr-expect: no property named " << name;
        failed = true;
        continue;
      }
      failed |= mlir::failed(check(module, argument));
    }
    markAllAnalysesPreserved();
    if (failed)
      signalPassFailure();
  }
};

} // namespace
