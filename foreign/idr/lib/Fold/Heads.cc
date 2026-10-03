// The folders of double_head and int_head: each calls the runtime's own C
// function on its constant operand, as idr.fold says.

#include "idr/Idr.h"

#include "idris_rt.h"

import idr.fold;

using namespace mlir;

namespace idr {

using fold::extended;
using fold::wrapped;

OpFoldResult DoubleHeadOp::fold(FoldAdaptor adaptor) {
  auto d = dyn_cast_or_null<FloatAttr>(adaptor.getValue());
  if (!d)
    return {};
  return wrapped(getType(), idris_rt_double_head(d.getValueAsDouble()));
}

OpFoldResult IntHeadOp::fold(FoldAdaptor adaptor) {
  auto n = dyn_cast_or_null<IntegerAttr>(adaptor.getValue());
  if (!n)
    return {};
  int64_t value = extended(n, getIsSigned());
  return wrapped(getType(), getIsSigned() ? idris_rt_int_head_s(value)
                                          : idris_rt_int_head_u(static_cast<uint64_t>(value)));
}

} // namespace idr
