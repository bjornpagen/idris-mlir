// idr-expect: checks the properties it is given, by name, and changes
// nothing. A request is `name` or `name=argument`; an unknown name is an
// error, so a misspelled property cannot pass.

#include "idr/Transforms/Expect.h"

#include "idr/IR/IdrDialect.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/Math/IR/Math.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Dialect/UB/IR/UBOps.h"

namespace idr {
#define GEN_PASS_DEF_IDREXPECT
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace {

struct Expect : idr::impl::IdrExpectBase<Expect> {
  using IdrExpectBase::IdrExpectBase;

  void runOnOperation() override {
    ModuleOp module = getOperation();
    // The properties share what they ask of the module: the symbol table,
    // the references among functions and the layouts are computed once,
    // by whichever property asks first.
    AnalysisManager analyses = getAnalysisManager();
    bool failed = false;
    for (StringRef request : holds) {
      auto [name, argument] = request.split('=');
      idr::expect::Check check = idr::expect::lookup(name);
      if (!check) {
        module.emitError() << "idr-expect: no property named " << name;
        failed = true;
        continue;
      }
      failed |= mlir::failed(check(module, analyses, argument));
    }
    markAllAnalysesPreserved();
    if (failed)
      signalPassFailure();
  }
};

} // namespace
