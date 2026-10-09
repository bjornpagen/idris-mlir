// A string that cannot be empty: a non-empty constant, or a string built
// with a character or a number in it. A guard of its head or its tail folds
// away on it, and a match on it never takes the case "".

#include "idr/Idr.h"

#include "mlir/IR/Matchers.h"

using namespace mlir;
using namespace idr;

bool idr::knownNonEmpty(Value value) {
  Attribute constant;
  if (matchPattern(value, m_Constant(&constant)))
    return checkHolds(CheckKind::Nonempty, constant);
  Operation *def = value.getDefiningOp();
  if (isa_and_nonnull<StrConsOp, StrFromCharOp, StrShowOp, BigShowOp>(def))
    return true;
  if (auto append = dyn_cast_or_null<StrAppendOp>(def))
    return knownNonEmpty(append.getLhs()) || knownNonEmpty(append.getRhs());
  return false;
}
