// Quantities as the IR spells them.

#include "Specialize/Quantity.h"

using namespace mlir;

namespace idr::specialize {

StringRef spell(Quantity q) {
  switch (q) {
  case Quantity::Zero:
    return "0";
  case Quantity::One:
    return "1";
  case Quantity::Many:
    return "w";
  }
  return "w";
}

Quantity quantityOf(Attribute spelled, Type type) {
  if (auto text = dyn_cast_or_null<StringAttr>(spelled)) {
    if (text.getValue() == "0")
      return Quantity::Zero;
    if (text.getValue() == "1")
      return Quantity::One;
    if (text.getValue() == "w")
      return Quantity::Many;
  }
  if (isa<ErasedType>(type))
    return Quantity::Zero;
  return isa<WorldType>(type) ? Quantity::One : Quantity::Many;
}

Quantity quantityOf(func::FuncOp fn, unsigned index) {
  return quantityOf(fn.getArgAttr(index, "idr.quantity"), fn.getArgumentTypes()[index]);
}

Quantity quantityOf(Operation *from, SymbolRefAttr ctor, unsigned index, Type type) {
  CtorOp decl = lookupCtor(from, ctor);
  ArrayAttr quantities = decl ? decl.getQuantities() : ArrayAttr();
  return quantityOf(quantities && index < quantities.size() ? quantities[index] : Attribute(),
                    type);
}

} // namespace idr::specialize
