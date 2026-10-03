// #idr.big: an Integer, in canonical decimal.

#include "idr/Idr.h"

using namespace mlir;
using namespace idr;

// One spelling per integer, so that equal bigs are equal attributes.
LogicalResult BigAttr::verify(function_ref<InFlightDiagnostic()> emitError,
                              StringRef value, Type) {
  StringRef digits = value;
  digits.consume_front("-");
  bool canonical = !digits.empty() && llvm::all_of(digits, llvm::isDigit) &&
                   (digits == "0" ? value == "0" : digits.front() != '0');
  if (!canonical)
    return emitError() << "expects a big in canonical decimal, got \"" << value << "\"";
  return success();
}
