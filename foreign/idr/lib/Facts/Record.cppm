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
  fn->setAttr("idr.effects", EffectAttr::get(fn.getContext(), effects.bits()));
}

} // namespace idr::facts
