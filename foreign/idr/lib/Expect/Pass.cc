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

// A clone's key names the function it was copied from: a specialization
// its origin's, a raised clone its callee's, which may be a clone in turn.
// A function no longer in the module ends the chain, and so does one met
// before, which only a module written by hand can hold.
bool isCloneOf(SymbolTable &symbols, StringRef name, StringRef origin) {
  llvm::SmallDenseSet<StringRef> seen;
  for (;;) {
    if (name == origin)
      return true;
    if (!seen.insert(name).second)
      return false;
    auto fn = symbols.lookup<func::FuncOp>(name);
    auto clone = fn ? fn->getAttrOfType<CloneAttr>("idr.clone") : CloneAttr();
    if (!clone)
      return false;
    Attribute key = clone.getKey();
    if (auto spec = dyn_cast<SpecKeyAttr>(key))
      name = spec.getOrigin().getValue();
    else if (auto apply = dyn_cast<KeyApplyAttr>(key))
      name = apply.getCallee().getValue();
    else
      name = cast<KeyApplyFieldAttr>(key).getCallee().getValue();
  }
}

namespace {

// Whether `loc` names `name`: a NameLoc of it, itself or inside the fused
// and call-site locations the passes wrap around it.
bool locationNames(Location loc, StringRef name) {
  if (auto named = dyn_cast<NameLoc>(loc))
    return named.getName() == name || locationNames(named.getChildLoc(), name);
  if (auto fused = dyn_cast<FusedLoc>(loc))
    return llvm::any_of(fused.getLocations(), [&](Location l) { return locationNames(l, name); });
  if (auto site = dyn_cast<CallSiteLoc>(loc))
    return locationNames(site.getCallee(), name);
  return false;
}

} // namespace

// Every function Emit writes carries the Idris name of its definition as its
// location (a NameLoc), and a clone of it keeps that location whatever the
// passes name the clone: the location is the provenance no pass drops, where
// a key attribute is stripped once its pass is done.
SmallVector<func::FuncOp> named(ModuleOp module, StringRef function, StringRef property) {
  SmallVector<func::FuncOp> functions;
  StringRef name = function.ltrim('@');
  if (name.empty()) {
    fail(module.getLoc(), property) << "no function named";
    return functions;
  }
  for (auto fn : module.getOps<func::FuncOp>())
    if (fn.getSymName() == name || locationNames(fn.getLoc(), name))
      functions.push_back(fn);
  if (functions.empty())
    fail(module.getLoc(), property) << "no function " << function << ", and no clone of it";
  return functions;
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
