// idr.fold:lists: constant lists.
export module idr.fold:lists;

import idr.mlir;
import idr.dialect;

using namespace mlir;

export namespace idr::fold {

// The elements of a constant list: a chain of constructors of two fields
// ending in one of none; nothing for any other constant.
std::optional<SmallVector<Attribute>> listElements(Attribute list) {
  SmallVector<Attribute> elements;
  while (true) {
    auto con = dyn_cast_or_null<ConAttr>(list);
    if (!con)
      return std::nullopt;
    ArrayAttr fields = con.getFields();
    if (fields.empty())
      return elements;
    if (fields.size() != 2)
      return std::nullopt;
    elements.push_back(fields[0]);
    list = fields[1];
  }
}

} // namespace idr::fold
