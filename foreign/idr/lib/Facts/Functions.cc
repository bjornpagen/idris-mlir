// The facts of a function: `idr.effects`, `idr.total` and `idr.library`.

#include "Facts/Facts.h"

using namespace mlir;
using namespace idr;

namespace {

bool holdsWorld(Operation *from, Type type, llvm::SmallDenseSet<Type> &seen) {
  type = unrestricted(type);
  if (isa<WorldType>(type))
    return true;
  DataOp data = lookupData(from, type);
  if (!data || !seen.insert(type).second)
    return false;
  return llvm::any_of(data.getCtors(), [&](CtorOp ctor) {
    return llvm::any_of(ctor.getFieldTypes().getAsValueRange<TypeAttr>(),
                        [&](Type field) { return holdsWorld(from, field, seen); });
  });
}

} // namespace

bool facts::mayHoldWorld(Operation *from, Type type) {
  llvm::SmallDenseSet<Type> seen;
  return holdsWorld(from, type, seen);
}

bool facts::takesWorld(func::FuncOp fn) {
  return llvm::any_of(fn.getArgumentTypes(),
                      [&](Type type) { return mayHoldWorld(fn, type); });
}

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

void facts::record(func::FuncOp fn, Effects effects) {
  Effect bits = Effect::none;
  if (effects.io)
    bits = bits | Effect::io;
  if (effects.crash)
    bits = bits | Effect::crash;
  fn->setAttr("idr.effects", EffectAttr::get(fn.getContext(), bits));
}

void facts::inherit(func::FuncOp made, func::FuncOp origin, ArrayRef<func::FuncOp> labels) {
  Effects effects = of(origin);
  for (func::FuncOp label : labels)
    effects |= of(label);
  effects.io |= takesWorld(made);
  record(made, effects);
  if (effects.partial)
    made->removeAttr("idr.total");
  else
    made->setAttr("idr.total", UnitAttr::get(made.getContext()));
}

bool facts::isLibrary(func::FuncOp fn) { return fn->hasAttr("idr.library"); }
