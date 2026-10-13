// The checks of the dialect's attributes beyond their syntax: a big has one
// spelling, and an instance key is text.

#include "idr/IR/IdrDialect.h"

#include "llvm/ADT/StringExtras.h"

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

// Every argument is the text the frontend prints for a type, an
// implementation or a shape: the key names, and refers to no symbol, so it
// keeps nothing alive and follows no rename.
LogicalResult InstanceAttr::verify(function_ref<InFlightDiagnostic()> emitError,
                                   StringAttr, ArrayAttr arguments) {
  if (!llvm::all_of(arguments, llvm::IsaPred<StringAttr>))
    return emitError() << "expects every argument of #idr.instance to be a string";
  return success();
}
