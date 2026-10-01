// A linear field of a constant constructor.

#include "idr/Idr.h"

#include "mlir/IR/Matchers.h"
#include "mlir/IR/PatternMatch.h"

using namespace mlir;
using namespace idr;

// The fold of a field of a constant is an attribute, and a constant is no
// linear value: folding shares equal constants, and a shared linear value
// would be used twice. A linear field of a constant is its value entered
// into the linear type instead, one entry per read, which the one use of
// the field then takes apart.
LogicalResult FieldOp::canonicalize(FieldOp field, PatternRewriter &rewriter) {
  Type type = field.getType();
  // A field of a known constructor read at another grade than the
  // constructor took it: the operand, held as read. A linear operand moves
  // out, so only the one read takes it.
  if (auto built = throughLinear(field.getValue()).getDefiningOp<ConOp>();
      built && built.getCtor().getLeafReference() == field.getCtorAttr().getAttr()) {
    auto index = static_cast<unsigned>(field.getIndex());
    Value operand = built.getFields()[index];
    if (operand.getType() == type ||
        (quantityOf(operand.getType()) == Quantity::One && !fieldReadOnce(built.getResult(), index)))
      return failure();
    rewriter.replaceOp(field, heldAs(rewriter, field.getLoc(), operand, type));
    return success();
  }
  ConAttr con;
  if (!isLinear(type) || !matchPattern(throughLinear(field.getValue()), m_Constant(&con)) ||
      con.getCtor().getLeafReference() != field.getCtorAttr().getAttr())
    return failure();
  Attribute value = con.getFields()[static_cast<unsigned>(field.getIndex())];
  Dialect *dialect = rewriter.getContext()->getLoadedDialect<IdrDialect>();
  Operation *plain = dialect->materializeConstant(rewriter, value, unrestricted(type), field.getLoc());
  if (!plain)
    return failure();
  rewriter.replaceOpWithNewOp<LinEnterOp>(field, type, plain->getResult(0));
  return success();
}
