// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// linker-names: from idr-lower on, a symbol is the name LLVM and the
// linker take, so every symbol the program defines is written in the one
// alphabet both read the same on every target: letters, digits, `_`, `.`
// and `$`.

#include "idr/Transforms/Expect.h"

#include "llvm/ADT/StringExtras.h"

using namespace mlir;

namespace idr::expect {

// Every symbol of the program's own table is in letters, digits, `_`, `.`
// and `$`.
LogicalResult linkerNames(const Request<Nothing> &request) {
  bool held = true;
  for (Operation &op : programOf(request.module)->getRegion(0).getOps()) {
    auto symbol = dyn_cast<SymbolOpInterface>(op);
    if (!symbol)
      continue;
    StringRef name = symbol.getName();
    auto spelled = [](char c) { return llvm::isAlnum(c) || c == '_' || c == '.' || c == '$'; };
    if (llvm::all_of(name, spelled))
      continue;
    fail(op.getLoc(), request.property) << "@" << name
                                        << " is written outside the linker's alphabet";
    held = false;
  }
  return success(held);
}

} // namespace idr::expect
