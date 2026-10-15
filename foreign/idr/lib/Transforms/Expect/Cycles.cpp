// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The graphs the properties of reach and recursion are stated over: the
// functions a body names by symbol, whatever op names them, before
// lowering and after it.

#include "idr/Transforms/Expect.h"

#include "idr/Support/Scc.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SetVector.h"

using namespace mlir;

namespace idr::expect {

// What a function's own attributes name is no use by its body, so only
// the uses inside the body count.
SmallVector<Operation *> callees(SymbolTable &symbols, Operation *fn) {
  llvm::SetVector<Operation *, SmallVector<Operation *>> out;
  Region &body = cast<FunctionOpInterface>(fn).getFunctionBody();
  if (std::optional<SymbolTable::UseRange> uses = SymbolTable::getSymbolUses(&body))
    for (const SymbolTable::SymbolUse &use : *uses)
      if (Operation *target = symbols.lookup(use.getSymbolRef().getRootReference());
          isa_and_nonnull<FunctionOpInterface>(target))
        out.insert(target);
  return out.takeVector();
}

SmallVector<SmallVector<Operation *>>
cycles(ArrayRef<Operation *> nodes, function_ref<SmallVector<Operation *>(Operation *)> edges) {
  SmallVector<SmallVector<Operation *>> out;
  for (SmallVector<Operation *> &component : idr::stronglyConnected<Operation *>(nodes, edges))
    if (component.size() > 1 || llvm::is_contained(edges(component.front()), component.front()))
      out.push_back(std::move(component));
  return out;
}

} // namespace idr::expect
