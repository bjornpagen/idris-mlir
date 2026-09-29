// Writes `idr.effects`.
module idr.facts;

import idr.mlir;

using namespace mlir;
using namespace idr;

void facts::record(func::FuncOp fn, Effects effects) {
  Effect bits = Effect::none;
  if (effects.io)
    bits = bits | Effect::io;
  if (effects.crash)
    bits = bits | Effect::crash;
  fn->setAttr("idr.effects", EffectAttr::get(fn.getContext(), bits));
}
