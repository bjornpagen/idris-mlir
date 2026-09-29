// output-fused: no string is built only to be written. Output of a
// concatenation, of a character before a string, of one character or of a
// number writes its pieces instead, so idr.io.put_str never writes what one
// of those builders made.

#include "Expect/Expect.h"

using namespace mlir;

namespace idr::expect {

LogicalResult outputFused(ModuleOp module, StringRef) {
  bool held = true;
  module.walk([&](PutStrOp put) {
    Operation *builder = put.getStr().getDefiningOp();
    if (!isa_and_nonnull<StrAppendOp, StrConsOp, StrFromCharOp, StrShowOp>(builder))
      return;
    fail(put.getLoc(), "output-fused")
        << "idr.io.put_str writes what " << builder->getName() << " built in " << where(put);
    held = false;
  });
  return success(held);
}

} // namespace idr::expect
