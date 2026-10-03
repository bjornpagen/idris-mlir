// Whether output writes a string in the pieces it is built of, where the
// patterns of Canonicalize.td take it apart.

#include "idr/Idr.h"

using namespace mlir;
using namespace idr;

bool idr::writtenInPieces(Value str) {
  Operation *builder = str.getDefiningOp();
  if (isa_and_nonnull<StrAppendOp, StrConsOp, StrFromCharOp, StrShowOp>(builder))
    return true;
  return isa_and_nonnull<StrPackOp, StrConcatOp>(builder) && str.hasOneUse();
}
