// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The graph the properties of recursion and allocation are stated over: the
// functions a body names by symbol, whatever op names them, before
// lowering and after it; its reach and its cycles are Expect.h's.

#include "idr/Transforms/Expect.h"

#include "llvm/ADT/STLExtras.h"

#include <algorithm>

using namespace mlir;

namespace idr::expect {

// What a function's own attributes name is no use by its body, so only
// the uses inside the body count. A body may name one function many times,
// so the numbers it names are sorted and each kept once: the program's
// order, the same in every run.
SmallVector<FunctionNumbering::Node> callees(const FunctionNumbering &numbering,
                                             SymbolTable &symbols, FunctionNumbering::Node fn) {
  SmallVector<FunctionNumbering::Node> named;
  Region &body = cast<FunctionOpInterface>(numbering[fn]).getFunctionBody();
  if (std::optional<SymbolTable::UseRange> uses = SymbolTable::getSymbolUses(&body))
    for (const SymbolTable::SymbolUse &use : *uses)
      if (Operation *target = symbols.lookup(use.getSymbolRef().getRootReference());
          isa_and_nonnull<FunctionOpInterface>(target))
        if (std::optional<FunctionNumbering::Node> id = numbering.idOf(target))
          named.push_back(*id);
  llvm::sort(named);
  named.erase(std::unique(named.begin(), named.end()), named.end());
  return named;
}

} // namespace idr::expect
