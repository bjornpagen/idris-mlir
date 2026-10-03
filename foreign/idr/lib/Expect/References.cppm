// A function's references to other functions, as the loop breakers see
// them.
export module idr.expect:references;

import idr.mlir;

using namespace mlir;

namespace idr::expect {

// A function refers to what it calls and to the functions its closures and
// closure constants name.
SmallVector<func::FuncOp> references(SymbolTable &symbols, func::FuncOp fn) {
  SmallVector<func::FuncOp> out;
  if (std::optional<SymbolTable::UseRange> uses = SymbolTable::getSymbolUses(&fn.getBody()))
    for (const SymbolTable::SymbolUse &use : *uses)
      if (auto target = symbols.lookup<func::FuncOp>(use.getSymbolRef().getRootReference()))
        out.push_back(target);
  return out;
}

} // namespace idr::expect
