// idr.facts:record: writes `idr.effects`.
export module idr.facts:record;

import idr.mlir;
import idr.dialect;

import :effects;

using namespace mlir;
using namespace idr;

export namespace idr::facts {

// Writes `idr.effects` when `fn` does not already carry `effects`.
// Returns whether the attribute was written.
bool record(func::FuncOp fn, Effects effects) {
  Attribute attr = EffectAttr::get(fn.getContext(), effects.bits());
  if (fn->getAttr("idr.effects") == attr)
    return false;
  fn->setAttr("idr.effects", attr);
  return true;
}

} // namespace idr::facts
