// What a call of a function may do, from `idr.effects` and `idr.total`.
module idr.facts;

import idr.mlir;

using namespace mlir;
using namespace idr;

facts::Effects facts::of(func::FuncOp fn) {
  Effects out = Effects::all();
  // A function the module does not have, or whose body it does not have, may
  // do anything.
  if (!fn || fn.isExternal())
    return out;
  out.partial = !fn->hasAttr("idr.total");
  if (auto found = fn->getAttrOfType<EffectAttr>("idr.effects")) {
    out.io = bitEnumContainsAny(found.getValue(), Effect::io);
    out.crash = bitEnumContainsAny(found.getValue(), Effect::crash);
  }
  return out;
}
