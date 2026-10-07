// The cells of closures, and of suspensions: one cell holds the captures
// and, once forced, the value, so it is as large as either.

module idr.layout;

import idr.mlir;
import idr.dialect;

using namespace mlir;

namespace idr::layout {

bool Layouts::placeClosures(Type pointer) {
  bool fits = true;
  SymbolTable symbols(module);
  for (auto [id, label] : llvm::enumerate(labels)) {
    SmallVector<Type> fields{pointer};
    llvm::append_range(fields, label.captureTypes());
    std::expected<Cell, std::string> cell =
        cellOf(fields, 1, [](unsigned objs) { return CellInfo::closure(objs); });
    if (!cell) {
      symbols.lookup(label.callee.getAttr())->emitError()
          << "unsupported (layout): a closure of @" << label.callee.getValue() << " with "
          << label.captures << " captures cannot be built: " << cell.error();
      fits = false;
      continue;
    }
    auto key = static_cast<unsigned>(id);
    closures[key] = std::make_unique<Cell>(std::move(*cell));
    if (!label.suspension)
      continue;
    if (label.type.getNumResults() != 1) {
      symbols.lookup(label.callee.getAttr())->emitError()
          << "unsupported (layout): a suspension of @" << label.callee.getValue()
          << " does not return one value";
      fits = false;
      continue;
    }
    SmallVector<Type> resultFields{pointer, label.type.getResult(0)};
    std::expected<Cell, std::string> forced =
        cellOf(resultFields, 1, [](unsigned objs) { return CellInfo::closure(objs); });
    if (!forced) {
      symbols.lookup(label.callee.getAttr())->emitError()
          << "unsupported (layout): the value of a suspension of @" << label.callee.getValue()
          << " cannot be stored in its cell: " << forced.error();
      fits = false;
      continue;
    }
    unsigned size = std::max(closures[key]->size, forced->size);
    closures[key]->size = size;
    forced->size = size;
    forcedCells[key] = std::make_unique<Cell>(std::move(*forced));
  }
  return fits;
}

} // namespace idr::layout
