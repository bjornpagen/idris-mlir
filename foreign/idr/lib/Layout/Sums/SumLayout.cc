// An unboxed sum's slots.
module idr.layout;

import idr.mlir;

using namespace mlir;

SmallVector<Type> idr::layout::SumLayout::types() const {
  SmallVector<Type> all;
  if (tag)
    all.push_back(tag);
  all.append(slots.begin(), slots.end());
  return all;
}

unsigned idr::layout::SumLayout::offset() const { return tag ? 1 : 0; }
