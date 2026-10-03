// idr.facts:of: what a call of a function may do, from `idr.effects`.
export module idr.facts:of;

import idr.mlir;
import idr.dialect;

import :effects;

using namespace mlir;
using namespace idr;

export namespace idr::facts {

// What a call of `fn` may do. A null function (one the module lacks), a
// function without a body, or one without `idr.effects` may do anything.
Effects of(func::FuncOp fn) {
  Effects out = Effects::all();
  // A function the module does not have, or whose body it does not have, may
  // do anything.
  if (!fn || fn.isExternal())
    return out;
  if (auto found = fn->getAttrOfType<EffectAttr>("idr.effects")) {
    out.io = bitEnumContainsAny(found.getValue(), Effect::io);
    out.crash = bitEnumContainsAny(found.getValue(), Effect::crash);
    out.diverge = bitEnumContainsAny(found.getValue(), Effect::diverge);
  }
  return out;
}

} // namespace idr::facts
