// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// linker-names: from the lowering on, a symbol is the name LLVM and the
// linker take. Every function the program defines carries the program's
// one prefix, so none is a runtime symbol or the C entry, and is written in
// the one alphabet both read the same on every target: letters, digits,
// `_`, `.` and `$`.

#include "idr/Transforms/Expect.h"

#include "llvm/ADT/StringExtras.h"

using namespace mlir;

namespace idr::expect {

// Every function of the program's own table that the program defines and
// keeps private (the process entry, the one public function, is the C
// entry's and takes no prefix) is `idr.` and then a name in letters,
// digits, `_`, `.` and `$`.
LogicalResult linkerNames(const Request<Nothing> &request) {
  static constexpr llvm::StringLiteral prefix = "idr.";
  bool held = true;
  for (Operation &op : programOf(request.module)->getRegion(0).getOps()) {
    auto fn = dyn_cast<FunctionOpInterface>(op);
    if (!fn || fn.isExternal() || !fn.isPrivate())
      continue;
    StringRef name = fn.getName();
    auto spelled = [](char c) { return llvm::isAlnum(c) || c == '_' || c == '.' || c == '$'; };
    if (!name.starts_with(prefix)) {
      fail(op.getLoc(), request.property) << "@" << name << " does not carry the program's prefix, "
                                          << prefix;
      held = false;
    } else if (!llvm::all_of(name, spelled)) {
      fail(op.getLoc(), request.property) << "@" << name
                                          << " is written outside the linker's alphabet";
      held = false;
    }
  }
  return success(held);
}

} // namespace idr::expect
