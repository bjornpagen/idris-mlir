// The facts of a function: `idr.effects`, `idr.total` and `idr.library`.

#include "Facts/Facts.h"

using namespace mlir;
using namespace idr;

namespace {

bool holdsWorld(Operation *from, Type type, llvm::SmallDenseSet<Type> &seen) {
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
  auto found = fn->getAttrOfType<EffectAttr>("idr.effects");
  // idr-specialize copies its origin's attributes to a clone and then
  // gives it the facts it computes as idr.effect and idr.may_crash, which
  // idr-effects writes too until idr-specialize gives its clones
  // idr.effects (inherit): both count.
  auto effect = fn->getAttrOfType<StringAttr>("idr.effect");
  if (!found && !effect)
    return out;
  out.io = out.crash = false;
  if (found) {
    out.io = bitEnumContainsAny(found.getValue(), Effect::io);
    out.crash = bitEnumContainsAny(found.getValue(), Effect::crash);
  }
  if (effect) {
    out.io |= effect.getValue() != "pure";
    out.crash |= fn->hasAttr("idr.may_crash");
  }
  // Arity raising gives a clone the world its consumer took, so a function
  // that takes a world performs IO whatever its copied attribute says.
  out.io |= llvm::any_of(fn.getArgumentTypes(), llvm::IsaPred<WorldType>);
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

// The old facts, which idr-specialize reads until it asks `of`: pure when
// idr-effects found that the function reaches no IO op (a closure counts
// where it is made), and able to crash unless idr-effects found it cannot.
bool idr::isPure(func::FuncOp fn) {
  auto effect = fn->getAttrOfType<StringAttr>("idr.effect");
  return effect && effect.getValue() == "pure";
}

bool idr::mayCrash(func::FuncOp fn) {
  return !fn->hasAttr("idr.effect") || fn->hasAttr("idr.may_crash");
}

bool idr::isTotal(func::FuncOp fn) { return fn->hasAttr("idr.total"); }
