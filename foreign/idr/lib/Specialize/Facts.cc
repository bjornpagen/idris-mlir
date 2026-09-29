// The facts of clones, from those of the functions they are made of.

#include "Specialize/Facts.h"

#include "mlir/IR/Matchers.h"

using namespace mlir;

namespace idr::specialize {

void inheritFacts(func::FuncOp clone, func::FuncOp origin, ArrayRef<func::FuncOp> labels,
                  bool writes) {
  auto effect = origin->getAttrOfType<StringAttr>("idr.effect");
  bool known = bool(effect);
  bool total = isTotal(origin);
  bool pure = effect && effect.getValue() == "pure";
  bool crash = !effect || origin->hasAttr("idr.may_crash");
  for (func::FuncOp label : labels) {
    if (!label) {
      total = false;
      continue;
    }
    auto labelEffect = label->getAttrOfType<StringAttr>("idr.effect");
    total &= isTotal(label);
    pure &= labelEffect && labelEffect.getValue() == "pure";
    crash |= !labelEffect || label->hasAttr("idr.may_crash");
  }
  pure &= !writes;
  MLIRContext *ctx = clone.getContext();
  if (total)
    clone->setAttr("idr.total", UnitAttr::get(ctx));
  else
    clone->removeAttr("idr.total");
  if (!known)
    return;
  clone->setAttr("idr.effect", StringAttr::get(ctx, pure ? "pure" : "effectful"));
  if (crash)
    clone->setAttr("idr.may_crash", UnitAttr::get(ctx));
  else
    clone->removeAttr("idr.may_crash");
}

bool evaluatesToTheEnd(func::FuncOp callee, ValueRange operands) {
  return isPure(callee) && isTotal(callee) &&
         llvm::all_of(operands, [](Value v) { return matchPattern(v, m_Constant()); });
}

} // namespace idr::specialize
