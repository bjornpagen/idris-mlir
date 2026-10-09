// idr.fold:lists: constant lists.
export module idr.fold:lists;

import idr.mlir;
import idr.dialect;

using namespace mlir;

export namespace idr::fold {

// The elements of a constant list: a chain of constructors of two fields
// ending in one of none; nothing for any other constant. A run along the
// second field is a stretch of the chain, read a cell at a time and then
// its tail, never through the rest of the run that reading the field would
// build.
std::optional<SmallVector<Attribute>> listElements(Attribute list) {
  SmallVector<Attribute> elements;
  while (true) {
    auto con = dyn_cast_or_null<ConAttr>(list);
    if (!con)
      return std::nullopt;
    if (con.isRun()) {
      // Each cell holds the constructor's fields but the spine.
      if (con.getRunCells().front().size() != 1)
        return std::nullopt;
      if (con.getSpine() == 1) {
        for (ArrayAttr cell : con.getRunCells())
          elements.push_back(cell[0]);
        list = con.getTail();
      } else {
        // Along the first field the run is this cell's element, a list
        // whose first element is a list again; the rest is off the spine.
        elements.push_back(con.getField(0));
        list = con.getField(1);
      }
      continue;
    }
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
