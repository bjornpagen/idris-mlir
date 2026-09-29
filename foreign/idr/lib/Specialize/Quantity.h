// Quantities, the semiring of QTT: how often a value is used, none, exactly
// once, or any number of times.
#pragma once

#include "idr/Idr.h"

#include <cstdint>

namespace idr::specialize {

enum class Quantity : uint8_t { Zero, One, Many };

// The quantity of a value used `b` times inside something used `a` times.
constexpr Quantity operator*(Quantity a, Quantity b) {
  if (a == Quantity::Zero || b == Quantity::Zero)
    return Quantity::Zero;
  return a == Quantity::One && b == Quantity::One ? Quantity::One : Quantity::Many;
}

// `idr.quantity`'s spelling.
llvm::StringRef spell(Quantity q);

// A quantity as `idr.quantity` or an `idr.ctor` spells it; one without a
// spelling is what its type allows: 0 for the erased value, 1 for a world,
// and any number of uses for the rest.
Quantity quantityOf(mlir::Attribute spelled, mlir::Type type);

// The quantity of parameter `index` of `fn`.
Quantity quantityOf(mlir::func::FuncOp fn, unsigned index);

// The quantity of field `index` of the constructor `ctor` names, from `from`.
Quantity quantityOf(mlir::Operation *from, mlir::SymbolRefAttr ctor, unsigned index,
                    mlir::Type type);

} // namespace idr::specialize
