// idr.canon:boundbyenclosing: a field a region of an enclosing match
// already binds.
export module idr.canon:boundbyenclosing;

import idr.mlir;
import idr.dialect;

using namespace mlir;
using namespace idr;

export namespace idr::canon {

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

} // namespace idr::canon
