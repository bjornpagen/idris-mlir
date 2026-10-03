// Whether each discardable attribute of an op is one someone reads.

#include "idr/Idr.h"

using namespace mlir;
using namespace idr;

namespace {

// The discardable attributes of no dialect that our own tools read. MLIR
// verifies a discardable attribute only through the dialect its name
// starts with, so any other name would be accepted and read by no one.
constexpr llvm::StringLiteral kOutsideDialects[] = {
    // What a test states lib/Facts answers about an op (idr-expect's
    // facts-as-marked).
    "expect.facts",
};

} // namespace

LogicalResult idr::verifyDiscardableAttrs(Operation *op) {
  // Another dialect verifies only the attributes it knows it reads, and
  // accepts the rest of its prefix; none of them is read on an idr op or a
  // function of a program, so these carry only the dialect's own.
  bool ours = isa_and_present<IdrDialect>(op->getDialect()) || isa<FunctionOpInterface>(op);
  for (NamedAttribute attr : op->getDiscardableAttrs()) {
    if (llvm::is_contained(kOutsideDialects, attr.getName().getValue()))
      continue;
    Dialect *dialect = attr.getNameDialect();
    if (!dialect)
      return op->emitOpError("has the attribute ")
             << attr.getName() << ", which no dialect defines";
    if (ours && !isa<IdrDialect>(dialect))
      return op->emitOpError("has the attribute ")
             << attr.getName() << ", which nothing reads on it";
  }
  return success();
}
