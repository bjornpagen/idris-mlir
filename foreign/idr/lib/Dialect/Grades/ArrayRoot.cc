// The array an access reads or writes, seen through its grades.

#include "idr/Idr.h"

using namespace mlir;
using namespace idr;

// A view or a share of an owned array is that array, of its length, and so
// is the array a linear position was entered with: what counting and
// linearity make of an array changes which value names it, not which cell
// it is.
Value idr::arrayRoot(Value array) {
  while (true) {
    Value next = throughLinear(array);
    if (auto borrow = next.getDefiningOp<BorrowOp>())
      next = borrow.getValue();
    else if (auto share = next.getDefiningOp<ShareOp>())
      next = share.getValue();
    if (next == array)
      return array;
    array = next;
  }
}
