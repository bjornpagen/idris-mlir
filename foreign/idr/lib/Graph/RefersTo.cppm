// idr.graph:refersto: the functions a body names, by a call, the label of a
// closure or suspension, or a closure constant: those that may run while it
// runs, and the edges the cycles of references follow.
export module idr.graph:refersto;

import idr.mlir;

using namespace mlir;

export namespace idr::graph {

// The functions of `symbols` that a symbol in the body of `fn` names, in the
// order its uses list them, once per use; none when the body holds an op
// whose uses are unknown.
SmallVector<func::FuncOp> refersTo(func::FuncOp fn, SymbolTable &symbols) {
  SmallVector<func::FuncOp> out;
  if (std::optional<SymbolTable::UseRange> uses = SymbolTable::getSymbolUses(&fn.getBody()))
    for (const SymbolTable::SymbolUse &use : *uses)
      if (auto target = symbols.lookup<func::FuncOp>(use.getSymbolRef().getRootReference()))
        out.push_back(target);
  return out;
}

} // namespace idr::graph
