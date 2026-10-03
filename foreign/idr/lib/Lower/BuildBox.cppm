// idr.lower:buildBox: a box's cell, as phase 2 builds it.
export module idr.lower:buildBox;

import idr.mlir;
import idr.dialect;
import idr.layout;

import :runtime;

using namespace mlir;

export namespace idr::lower {

// A box's cell: count 1 and its info word, then its fields' components
// stored at their offsets.
Value buildBox(OpBuilder &b, Location loc, layout::Layouts &layouts, Runtime &runtime, CtorOp ctor,
               Value cell, ArrayRef<ValueRange> fields) {
  const layout::Cell &layout = layouts.box(ctor);
  if (!cell)
    cell = runtime.allocate(b, loc, layout.size, layout.info);
  for (auto [slots, values] : llvm::zip_equal(layout.fields, fields))
    runtime.store(b, loc, cell, slots, values);
  return cell;
}

} // namespace idr::lower
