// A string that cannot be empty: a non-empty constant, or a string built
// with a character or a number in it. A guard of its head or its tail folds
// away on it, and a match on it never takes the case "".

#include "idr/Idr.h"

#include "mlir/IR/Matchers.h"

using namespace mlir;
using namespace idr;

bool idr::knownNonEmpty(Value value) {
  // Appends share subexpressions. Walking both sides of each without
  // remembering a value walks the shared part again on every path.
  SmallVector<Value> work{value};
  llvm::SmallPtrSet<Value, 8> seen;
  while (!work.empty()) {
    Value next = work.pop_back_val();
    if (!seen.insert(next).second)
      continue;
    Attribute constant;
    if (matchPattern(next, m_Constant(&constant))) {
      if (checkHolds(CheckKind::Nonempty, constant))
        return true;
      continue;
    }
    Operation *def = next.getDefiningOp();
    if (isa_and_nonnull<StrConsOp, StrFromCharOp, StrShowOp, BigShowOp>(def))
      return true;
    if (auto append = dyn_cast_or_null<StrAppendOp>(def)) {
      work.push_back(append.getLhs());
      work.push_back(append.getRhs());
    }
  }
  return false;
}
