// one-clone: every call of a function, or of a clone of it, calls one and
// the same function: the calls share one specialization (or none was
// made), however many copies the passes made on the way.
export module idr.expect:clones;

import idr.mlir;
import idr.dialect;

import :report;

using namespace mlir;

namespace idr::expect {

namespace {

// Whether the function named `name` is `origin` or a clone of it: a
// specialization or a raised copy whose chain of keys (idr.clone) leads to
// `origin`.
//
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

} // namespace

// Every call of the function the argument names, or of a clone of it, calls
// one and the same function.
export LogicalResult oneClone(ModuleOp module, StringRef function) {
  constexpr StringRef property = "one-clone";
  StringRef origin = function.ltrim('@');
  if (origin.empty())
    return fail(module.getLoc(), property) << "name the function, as one-clone=@f";
  SymbolTable symbols(module);
  llvm::SetVector<StringRef> targets;
  module.walk([&](func::CallOp call) {
    if (isCloneOf(symbols, call.getCallee(), origin))
      targets.insert(call.getCallee());
  });
  if (targets.empty())
    return fail(module.getLoc(), property) << "no call of " << function << " or of a clone of it";
  if (targets.size() == 1)
    return success();
  InFlightDiagnostic error = fail(module.getLoc(), property)
                             << "the calls of " << function << " reach";
  for (StringRef target : targets)
    error << " @" << target;
  return failure();
}

} // namespace idr::expect
