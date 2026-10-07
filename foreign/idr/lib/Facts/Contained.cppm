// idr.facts:contained: whether a value of a type may hold something, through
// the fields of the data it is. What it may hold is the caller's question;
// the walk is the same for each.
export module idr.facts:contained;

import idr.mlir;
import idr.dialect;

using namespace mlir;
using namespace idr;

export namespace idr::facts {

// Whether a value of `type` may hold what `holds` recognizes. `holds` sees
// the type with its grade removed, and the data declaration it names when
// it names one: a world, a closure, a sum of closures. A field of data may
// hold it too. A cycle of data holds nothing further. A linear value holds
// what its value does (`unrestricted`).
template <typename Holds>
bool contained(Operation *from, Type type, Holds holds) {
  llvm::SmallDenseSet<Type> seen;
  auto walk = [&](auto &walk, Type type) -> bool {
    type = unrestricted(type);
    DataOp data = lookupData(from, type);
    if (holds(type, data))
      return true;
    if (!data || !seen.insert(type).second)
      return false;
    return llvm::any_of(data.getCtors(), [&](CtorOp ctor) {
      return llvm::any_of(ctor.getFieldTypes().getAsValueRange<TypeAttr>(),
                          [&](Type field) { return walk(walk, field); });
    });
  };
  return walk(walk, type);
}

} // namespace idr::facts
