// The elimination of a value that begins at one of its uses: an apply of
// the value or of one field of it, through linear positions passed at once.

#include "idr/Idr.h"

using namespace mlir;
using namespace idr;

std::optional<idr::Elimination> idr::eliminationAt(OpOperand &use) {
  // The only user of `v`, if it has one.
  auto next = [](Value v) { return v.hasOneUse() ? *v.user_begin() : nullptr; };
  Elimination e;
  Value value = use.get();
  Operation *user = use.getOwner();
  if ((e.enter = dyn_cast<LinEnterOp>(user))) {
    e.exit = dyn_cast_or_null<LinUseOp>(next(e.enter.getResult()));
    if (!e.exit)
      return std::nullopt;
    user = next(value = e.exit.getResult());
  }
  if ((e.field = dyn_cast_or_null<FieldOp>(user)))
    user = next(value = e.field.getResult());
  if ((e.use = dyn_cast_or_null<LinUseOp>(user)))
    user = next(value = e.use.getResult());
  e.apply = dyn_cast_or_null<ApplyOp>(user);
  if (!e.apply || e.apply.getCallee() != value)
    return std::nullopt;
  return e;
}
