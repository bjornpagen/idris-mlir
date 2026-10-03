// The string a constant list of characters packs to, or a constant list of
// strings concatenates to, as the runtime builds it; and the folders of
// idr.str.pack and idr.str.concat, which are that string.

#include "idr/Idr.h"

#include "idris_rt.h"

import idr.fold;

using namespace mlir;

namespace idr {

using fold::listElements;
using fold::Scope;

Attribute stringOfList(MLIRContext *ctx, Attribute list) {
  std::optional<SmallVector<Attribute>> elements = listElements(list);
  if (!elements)
    return {};
  Scope scope(ctx);
  const idris_rt_str *s = scope.str(StringAttr::get(ctx, ""));
  if (llvm::all_of(*elements, [](Attribute c) { return isa<IntegerAttr>(c); })) {
    for (Attribute c : llvm::reverse(*elements))
      s = scope.keep(idris_rt_str_cons(static_cast<int32_t>(cast<IntegerAttr>(c).getInt()), s));
    return scope.attr(s);
  }
  if (!llvm::all_of(*elements, [](Attribute p) { return isa<StringAttr>(p); }))
    return {};
  for (Attribute p : *elements)
    s = scope.keep(idris_rt_str_append(s, scope.str(cast<StringAttr>(p))));
  return scope.attr(s);
}

OpFoldResult StrPackOp::fold(FoldAdaptor adaptor) {
  return stringOfList(getContext(), adaptor.getList());
}

OpFoldResult StrConcatOp::fold(FoldAdaptor adaptor) {
  return stringOfList(getContext(), adaptor.getList());
}

} // namespace idr
