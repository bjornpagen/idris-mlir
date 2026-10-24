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
// the uses inside the body count. A symbol may name something other than
// a function (a global), which is no callee. A body may name one function
// many times, so the ids it names are sorted and each kept once: id order,
// the same in every run.
SmallVector<WalkNumbering::Node> callees(const WalkNumbering &numbering, SymbolTable &symbols,
                                         WalkNumbering::Node fn) {
  SmallVector<WalkNumbering::Node> named;
  Region &body = numbering.op(fn).getFunctionBody();
  if (std::optional<SymbolTable::UseRange> uses = SymbolTable::getSymbolUses(&body))
    for (const SymbolTable::SymbolUse &use : *uses)
      if (auto target = symbols.lookup<FunctionOpInterface>(use.getSymbolRef().getRootReference()))
        named.push_back(numbering.id(target));
  llvm::sort(named);
  named.erase(std::unique(named.begin(), named.end()), named.end());
  return named;
}

} // namespace idr::expect
