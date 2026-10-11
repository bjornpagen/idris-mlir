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
//
// `memo`, when a pass has opened one, remembers the answer for each type
// once its walk has finished. `world` selects which of its two answers.
// A type already being walked is a cycle and is not remembered until that
// walk finishes: remembering it early would answer false for a type that a
// later field shows does hold something.
template <typename Holds>
bool contained(Operation *from, Type type, Holds holds, HoldMemo *memo = nullptr,
               bool world = false) {
  auto known = [&](Type type) -> std::optional<bool> {
    if (!memo)
      return std::nullopt;
    return world ? memo->world(type) : memo->closure(type);
  };
  auto remember = [&](Type type, bool answer) {
    if (!memo)
      return;
    if (world)
      memo->rememberWorld(type, answer);
    else
      memo->rememberClosure(type, answer);
  };
  llvm::SmallDenseSet<Type> seen;
  auto walk = [&](auto &walk, Type type) -> bool {
    type = unrestricted(type);
    if (std::optional<bool> answer = known(type))
      return *answer;
    DataOp data = lookupData(from, type);
    if (holds(type, data)) {
      remember(type, true);
      return true;
    }
    if (!data) {
      remember(type, false);
      return false;
    }
    if (!seen.insert(type).second)
      return false;
    bool answer = llvm::any_of(data.getCtors(), [&](CtorOp ctor) {
      return llvm::any_of(ctor.getFieldTypes().getAsValueRange<TypeAttr>(),
                          [&](Type field) { return walk(walk, field); });
    });
    remember(type, answer);
    return answer;
  };
  return walk(walk, type);
}

} // namespace idr::facts
