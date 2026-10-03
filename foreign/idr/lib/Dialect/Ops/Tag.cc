// idr.tag: the tag of a constructor value.

#include "idr/Idr.h"

#include "mlir/IR/Matchers.h"

import idr.ops;

using namespace mlir;
using namespace idr;

// The tag of a known constructor, or 0 for a type of one constructor.
OpFoldResult TagOp::fold(FoldAdaptor adaptor) {
  auto tag = [&](CtorOp ctor) -> OpFoldResult {
    if (!ctor)
      return {};
    return IntegerAttr::get(getType(), static_cast<int64_t>(ctor.getTag()));
  };
  Value source = throughLinear(getValue());
  if (auto con = source.getDefiningOp<ConOp>())
    return tag(lookupCtor(*this, con.getCtor()));
  auto con = dyn_cast_or_null<ConAttr>(adaptor.getValue());
  if (con || matchPattern(source, m_Constant(&con)))
    return tag(lookupCtor(*this, con.getCtor()));
  if (DataOp data = lookupData(*this, getValue().getType()))
    if (data.getCtors().size() == 1)
      return tag(data.getCtors().front());
  return {};
}

void TagOp::inferResultRanges(ArrayRef<ConstantIntRanges>, SetIntRangeFn setResultRange) {
  DataOp data = lookupData(*this, getValue().getType());
  size_t count = data ? data.getCtors().size() : 0;
  unsigned width = getType().getIntOrFloatBitWidth();
  setResultRange(getResult(), count == 0 ? ConstantIntRanges::maxRange(width)
                                         : ops::nonNegative(width, 0, count - 1));
}
