// idr-expect: checks the properties it is given, by name, and changes
// nothing. A request is `name` or `name=argument`; an unknown name is an
// error, so a misspelled property cannot pass.

#include "Expect/Expect.h"

#include "llvm/ADT/StringSwitch.h"

using namespace mlir;

namespace idr {
#define GEN_PASS_DEF_IDREXPECT
#include "idr/Passes.h.inc"
} // namespace idr

namespace idr::expect {

InFlightDiagnostic fail(Location loc, StringRef property) {
  return emitError(loc) << "expected " << property << ": ";
}

std::string where(Operation *op) {
  auto fn = isa<func::FuncOp>(op) ? cast<func::FuncOp>(op) : op->getParentOfType<func::FuncOp>();
  return fn ? ("@" + fn.getSymName()).str() : std::string("the module");
}

func::FuncOp named(ModuleOp module, StringRef function, StringRef property) {
  auto fn = SymbolTable(module).lookup<func::FuncOp>(function.ltrim('@'));
  if (!fn)
    fail(module.getLoc(), property) << "no function " << (function.empty() ? "named" : function);
  return fn;
}

} // namespace idr::expect

namespace {

idr::expect::Check lookup(StringRef name) {
  using namespace idr::expect;
  return llvm::StringSwitch<Check>(name)
      .Case("no-closures", noClosures)
      .Case("no-heap-allocation", noHeapAllocation)
      .Case("every-cycle-has-breaker", everyCycleHasBreaker)
      .Case("one-clone", oneClone)
      .Case("quantities-kept", quantitiesKept)
      .Case("reuses-in-place", reusesInPlace)
      .Case("counts-nothing", countsNothing)
      .Case("tests-nothing", testsNothing)
      .Case("resets-unshared", resetsUnshared)
      .Case("reuses-every-cell", reusesEveryCell)
      .Case("contified", contified)
      .Case("facts-as-marked", factsAsMarked)
      .Case("output-fused", outputFused)
      .Case("folds-balanced", foldsBalanced)
      .Case("constant-stack", constantStack)
      .Case("counted-loop", countedLoop)
      .Case("word-loop", wordLoop)
      .Default(nullptr);
}

struct Expect : idr::impl::IdrExpectBase<Expect> {
  using IdrExpectBase::IdrExpectBase;

  void runOnOperation() override {
    ModuleOp module = getOperation();
    bool failed = false;
    for (StringRef request : holds) {
      auto [name, argument] = request.split('=');
      idr::expect::Check check = lookup(name);
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
