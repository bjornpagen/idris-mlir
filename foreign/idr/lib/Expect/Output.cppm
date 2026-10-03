// output-fused: no string is built only to be written. Output of a
// concatenation, of a character before a string, of one character or of a
// number writes its pieces instead, and output of a list packed or
// concatenated only to be written writes the list's elements; so
// idr.io.put_str never writes what one of those builders made for it.
export module idr.expect:output;

import idr.mlir;
import idr.dialect;

import :report;

using namespace mlir;

namespace idr::expect {

// No string is built only to be written: idr.io.put_str never writes what
// idr.str.append, cons, from_char or show made.
export LogicalResult outputFused(ModuleOp module, StringRef) {
  bool held = true;
  module.walk([&](PutStrOp put) {
    if (!writtenInPieces(put.getStr()))
      return;
    fail(put.getLoc(), "output-fused") << "idr.io.put_str writes what "
                                       << put.getStr().getDefiningOp()->getName() << " built in "
                                       << where(put);
    held = false;
  });
  return success(held);
}

} // namespace idr::expect
