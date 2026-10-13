// The constant captures of a closure constant, as the call an apply of it
// becomes passes them, and the fields a constructor or a suspension folds
// with.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Canon.h"
#include "idr/IR/Grades.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/IR/PatternMatch.h"

using namespace mlir;
using namespace idr;

namespace idr::canon {

Value materialize(PatternRewriter &rewriter, Location loc, Attribute value, Type type) {
  Dialect *dialect = rewriter.getContext()->getLoadedDialect<IdrDialect>();
  Value plain = dialect->materializeConstant(rewriter, value, unrestricted(type), loc)->getResult(0);
  if (!isLinear(type))
    return plain;
  return LinEnterOp::create(rewriter, loc, type, plain);
}

bool buildable(Attribute value, Type type) {
  return ConstantOp::isBuildableWith(value, unrestricted(type)) ||
         arith::ConstantOp::isBuildableWith(value, unrestricted(type));
}

} // namespace idr::canon
