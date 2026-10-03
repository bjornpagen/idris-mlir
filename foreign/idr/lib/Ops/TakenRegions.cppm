// idr.ops:takenregions: the region a match takes, for its key or because
// an enclosing match on the same value took one.
export module idr.ops:takenregions;

import idr.mlir;
import idr.dialect;

export namespace idr::ops {

// The region of `Match` taken for the key `key`: its case, else the default.
template <typename Match>
mlir::Region *takenRegion(Match op, mlir::Attribute key) {
  const auto *it = llvm::find(op.getCases(), key);
  if (it != op.getCases().end())
    return &op.getCaseRegion(static_cast<unsigned>(it - op.getCases().begin()));
  return op.getDefaultRegion();
}

// The region a match takes because it sits in a region of another match on
// the same value: in a case of the enclosing match the value has that
// case's key, and in its default it has none of its keys, so a match whose
// keys are all among them takes its default. A match on a value no
// enclosing match took is known no better; the enclosing match's default
// says too little when this match has a key of its own, and the search
// goes on outward. Only the value matters, not the position it is held in:
// the same value in a linear position is still that value.
template <typename Match>
mlir::Region *takenFromEnclosing(Match op) {
  mlir::Value source = idr::throughLinear(op.getScrutinee());
  for (mlir::Region *region = op->getParentRegion(); region; region = region->getParentRegion()) {
    auto outer = mlir::dyn_cast<Match>(region->getParentOp());
    if (!outer || idr::throughLinear(outer.getScrutinee()) != source)
      continue;
    unsigned index = region->getRegionNumber();
    if (index < outer.getCases().size())
      return takenRegion(op, outer.getCases()[index]);
    mlir::Region *fallback = op.getDefaultRegion();
    if (fallback && llvm::all_of(op.getCases(), [&](mlir::Attribute key) {
          return llvm::is_contained(outer.getCases(), key);
        }))
      return fallback;
  }
  return nullptr;
}

} // namespace idr::ops
