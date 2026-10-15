// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The arguments of the properties stated of a function and of something
// more: `@f:<what>`, and the lists of functions some of them take.

#include "idr/Transforms/Expect.h"

using namespace mlir;

namespace idr::expect {

std::pair<StringRef, StringRef> splitAt(ModuleOp module, StringRef argument, StringRef property) {
  auto [function, rest] = argument.split(':');
  if (function.ltrim('@').empty() || rest.empty() || function.size() == argument.size()) {
    fail(module.getLoc(), property) << "name the function and what is stated of it, as "
                                    << property << "=@f:<...>";
    return {StringRef(), StringRef()};
  }
  return {function.trim(), rest.trim()};
}

SmallVector<StringRef> symbolList(StringRef list) {
  SmallVector<StringRef> out;
  list = list.trim();
  if (!list.consume_front("["))
    return {list.ltrim('@')};
  list.consume_back("]");
  SmallVector<StringRef> parts;
  list.split(parts, ',', -1, /*KeepEmpty=*/false);
  for (StringRef part : parts)
    if (StringRef name = part.trim().ltrim('@'); !name.empty())
      out.push_back(name);
  return out;
}

// A callee the module holds is asked whether it is made from `g`, so a
// call of a copy of g is a call of g; a callee it does not hold (a
// runtime function after lowering is declared, so it is held) is its
// symbol alone.
bool callsNamed(CallOpInterface call, StringRef g, SymbolTable &symbols) {
  auto callee = dyn_cast<SymbolRefAttr>(call.getCallableForCallee());
  if (!callee)
    return false;
  StringAttr root = callee.getRootReference();
  if (root.getValue() == g)
    return true;
  auto fn = symbols.lookup<FunctionOpInterface>(root);
  return fn && names(fn, g);
}

} // namespace idr::expect
