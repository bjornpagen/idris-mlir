// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The graph the properties of recursion and allocation are stated over: the
// functions a body names by symbol, whatever op names them, before
// lowering and after it; its reach and its cycles are Expect.h's.

#include "idr/Transforms/Expect.h"

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

} // namespace idr::expect
