// idr.graph:symboluses: the uses of each symbol of a module, from one walk
// of the module. SymbolTable::getSymbolUses(symbol, module) walks the whole
// module for one symbol, so asking it for every function of a module of
// thousands of functions walks the module thousands of times.
export module idr.graph:symboluses;

import idr.mlir;

using namespace mlir;

export namespace idr::graph {

class SymbolUses {
public:
  explicit SymbolUses(ModuleOp module) {
    std::optional<SymbolTable::UseRange> uses =
        SymbolTable::getSymbolUses(&module.getBodyRegion());
    known = uses.has_value();
    if (!uses)
      return;
    for (const SymbolTable::SymbolUse &use : *uses)
      bySymbol[use.getSymbolRef().getRootReference()].push_back(use);
  }

  // The uses of `symbol`, a symbol of the module, in the order
  // SymbolTable::getSymbolUses(symbol, module) gives them, and none where
  // that gives none: when the module holds an op whose uses are unknown.
  // Valid until the module changes.
  std::optional<ArrayRef<SymbolTable::SymbolUse>> of(Operation *symbol) const {
    if (!known)
      return std::nullopt;
    auto it = bySymbol.find(SymbolTable::getSymbolName(symbol));
    if (it == bySymbol.end())
      return ArrayRef<SymbolTable::SymbolUse>();
    return ArrayRef<SymbolTable::SymbolUse>(it->second);
  }

private:
  bool known = false;
  DenseMap<StringAttr, SmallVector<SymbolTable::SymbolUse, 2>> bySymbol;
};

} // namespace idr::graph
