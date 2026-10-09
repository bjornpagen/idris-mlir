// idr.specialize:shapeof: taking a value's shape.
export module idr.specialize:shapeof;

import idr.mlir;
import idr.dialect;

import :pattern;

using namespace mlir;

namespace idr::specialize {

namespace {

// A constant the clone builds again as it was built here: the value of an
// op the dialect materializes, as rebuild does. Erased is not constant.
bool constant(Value value, Attribute &out) {
  return !isErased(value.getType()) &&
         isa_and_nonnull<ConstantOp, arith::ConstantOp>(value.getDefiningOp()) &&
         matchPattern(value, m_Constant(&out));
}

} // namespace

} // namespace idr::specialize

export namespace idr::specialize {

// The pattern of `value`: its runtime leaves are appended to `leaves`, and
// its holes numbered from the size `leaves` had. A constant the clone would
// not build again is a leaf, as is a value of erased type (erased is not
// constant) and a linear value, whose shape its one use keeps.
Pattern shapeOf(mlir::Value value, llvm::SmallVectorImpl<mlir::Value> &leaves) {
  auto shapesOf = [&](ValueRange values) {
    std::vector<Pattern> out;
    for (Value part : values)
      out.push_back(shapeOf(part, leaves));
    return out;
  };
  Attribute known;
  if (constant(value, known))
    return {Constant{known}, value.getType(), builtAt(value)};
  if (auto con = value.getDefiningOp<ConOp>())
    return {Con{con.getCtorAttr(), shapesOf(con.getFields())}, value.getType(), builtAt(value)};
  if (auto closure = value.getDefiningOp<ClosureOp>())
    return {Closure{closure.getCalleeAttr(), shapesOf(closure.getCaptures())}, value.getType(),
            builtAt(value)};
  if (auto enter = value.getDefiningOp<LinEnterOp>()) {
    Pattern inner = shapeOf(enter.getValue(), leaves);
    if (!inner.isHole())
      return {Linear{{std::move(inner)}}, value.getType(), builtAt(value)};
    // A leaf that entered is a leaf itself: the entry stays with the caller.
    leaves.pop_back();
  }
  leaves.push_back(value);
  return leafOf(value, static_cast<unsigned>(leaves.size() - 1));
}

} // namespace idr::specialize
