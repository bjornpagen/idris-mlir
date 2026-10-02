// A field of a value whose constructor is known where it is read: a
// constant, an idr.con, or the case of an enclosing match on the value.

#include "idr/Idr.h"

#include "mlir/IR/Matchers.h"
#include "mlir/IR/PatternMatch.h"

using namespace mlir;
using namespace idr;

namespace {

// The argument of an enclosing match's case region that binds the field
// `field` reads, or nothing: the match is on the same value, at a grade
// that reads its fields rather than taking them apart (a match on a linear
// value moves each field into its one region argument, which a second read
// could not share), and the region is the case of the field's constructor.
Value boundByEnclosing(FieldOp field) {
  Value source = throughLinear(field.getValue());
  for (Region *region = field->getParentRegion(); region; region = region->getParentRegion()) {
    auto match = dyn_cast<MatchOp>(region->getParentOp());
    if (!match || throughLinear(match.getScrutinee()) != source)
      continue;
    if (quantityOf(match.getScrutinee().getType()) == Quantity::One)
      return {};
    unsigned index = region->getRegionNumber();
    if (index >= match.getCases().size() ||
        cast<FlatSymbolRefAttr>(match.getCases()[index]).getAttr() != field.getCtorAttr().getAttr())
      return {};
    BlockArgument arg = region->getArgument(static_cast<unsigned>(field.getIndex()));
    if (quantityOf(arg.getType()) == Quantity::One ||
        unrestricted(arg.getType()) != unrestricted(field.getType()))
      return {};
    return arg;
  }
  return {};
}

} // namespace

// The fold of a field of a constant is an attribute, and a constant is no
// linear value: folding shares equal constants, and a shared linear value
// would be used twice. A linear field of a constant is its value entered
// into the linear type instead, one entry per read, which the one use of
// the field then takes apart.
LogicalResult FieldOp::canonicalize(FieldOp field, PatternRewriter &rewriter) {
  Type type = field.getType();
  // A field of a known constructor read at another grade than the
  // constructor took it: the operand, held as read. A linear operand moves
  // out, so only the one read takes it; a pending operand (a field the
  // constructor was built without) is no value yet, and is never read.
  if (auto built = throughLinear(field.getValue()).getDefiningOp<ConOp>();
      built && built.getCtor().getLeafReference() == field.getCtorAttr().getAttr()) {
    auto index = static_cast<unsigned>(field.getIndex());
    Value operand = built.getFields()[index];
    if (operand.getDefiningOp<PendingOp>() || operand.getType() == type ||
        (quantityOf(operand.getType()) == Quantity::One && !fieldReadOnce(built.getResult(), index)))
      return failure();
    rewriter.replaceOp(field, heldAs(rewriter, field.getLoc(), operand, type));
    return success();
  }
  // A field read in the case of a match on the value: the region already
  // binds it, so the read is that argument, held as read.
  if (Value bound = boundByEnclosing(field)) {
    rewriter.replaceOp(field, heldAs(rewriter, field.getLoc(), bound, type));
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
