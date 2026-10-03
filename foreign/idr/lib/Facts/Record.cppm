// idr.facts:record: writes `idr.effects`.
export module idr.facts:record;

import idr.mlir;
import idr.dialect;

import :effects;

using namespace mlir;
using namespace idr;

export namespace idr::facts {

// Writes what idr-effects found as `idr.effects`.
void record(func::FuncOp fn, Effects effects) {
  Effect bits = Effect::none;
  if (effects.io)
    bits = bits | Effect::io;
  if (effects.crash)
    bits = bits | Effect::crash;
  if (effects.diverge)
    bits = bits | Effect::diverge;
  fn->setAttr("idr.effects", EffectAttr::get(fn.getContext(), bits));
}

} // namespace idr::facts
