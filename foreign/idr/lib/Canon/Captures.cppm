// idr.canon:captures: the constant captures of a closure constant, as the
// call an apply of it becomes passes them.
export module idr.canon:captures;

import idr.mlir;
import idr.dialect;

using namespace mlir;
using namespace idr;

export namespace idr::canon {

// A constant capture, as the parameter it fills takes it: a linear
// parameter takes the constant entered into its linear type.
Value materialize(PatternRewriter &rewriter, Location loc, Attribute value, Type type) {
  Dialect *dialect = rewriter.getContext()->getLoadedDialect<IdrDialect>();
  Value plain = dialect->materializeConstant(rewriter, value, unrestricted(type), loc)->getResult(0);
  if (!isLinear(type))
    return plain;
  return LinEnterOp::create(rewriter, loc, type, plain);
}

// Whether `materialize` can build `value` for a parameter of `type`.
bool buildable(Attribute value, Type type) {
  return ConstantOp::isBuildableWith(value, unrestricted(type)) ||
         arith::ConstantOp::isBuildableWith(value, unrestricted(type));
}

} // namespace idr::canon
