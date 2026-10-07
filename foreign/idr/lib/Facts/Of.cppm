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
  // A function the module does not have, or whose body it does not have, or
  // one idr-effects has not marked, may do anything.
  if (!fn || fn.isExternal())
    return Effects::all();
  if (auto found = fn->getAttrOfType<EffectAttr>("idr.effects"))
    return Effects::from(found.getValue());
  return Effects::all();
}

} // namespace idr::facts
