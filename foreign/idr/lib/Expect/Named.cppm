// idr.expect:named: the functions a property names.
export module idr.expect:named;

import idr.mlir;

import :report;

using namespace mlir;

namespace idr::expect {

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
SmallVector<FunctionOpInterface> namedFunctions(ModuleOp module, StringRef function,
                                                StringRef property) {
  SmallVector<FunctionOpInterface> functions;
  StringRef name = function.ltrim('@');
  if (name.empty()) {
    fail(module.getLoc(), property) << "no function named";
    return functions;
  }
  for (auto fn : module.getOps<FunctionOpInterface>())
    if (SymbolTable::getSymbolName(fn) == name || locationNames(fn.getLoc(), name))
      functions.push_back(fn);
  if (functions.empty())
    fail(module.getLoc(), property) << "no function " << function << ", and no clone of it";
  return functions;
}

// The functions `function` (`@f`) names: @f itself, when the module still
// has it, and every clone of it (a specialization, a raised copy), which
// keeps the location that names the definition it was copied from; or
// none, after the error that `property` names no function. A property
// stated of @f holds of all of them.
SmallVector<func::FuncOp> named(ModuleOp module, StringRef function, StringRef property) {
  SmallVector<FunctionOpInterface> all = namedFunctions(module, function, property);
  SmallVector<func::FuncOp> functions;
  for (FunctionOpInterface fn : all)
    if (auto f = dyn_cast<func::FuncOp>(fn.getOperation()))
      functions.push_back(f);
  if (functions.empty() && !all.empty())
    fail(module.getLoc(), property) << function << " is lowered: the property is of a module before idr-lower";
  return functions;
}

} // namespace idr::expect
