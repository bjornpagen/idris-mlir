// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What each key's sum is called: a name made from the key's content, so
// that no creation order reaches it. Every key becomes a sum: none is
// refused.

#include "idr/IR/IdrDialect.h"
#include "idr/Analysis/Labels.h"
#include "idr/IR/Symbols.h"
#include "idr/Transforms/Defunctionalize.h"

#include "mlir/IR/BuiltinOps.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/Support/raw_ostream.h"

#include <string>

using namespace mlir;

namespace idr::defunctionalize {

namespace {

// The bytes a key's name is made from: its carrier's canonical hash, which
// no printing flag reaches and which `names` keeps, so a carrier is printed
// once however many keys share it, then each label, in name order, after a
// NUL.
std::string keyText(ContentNames &names, const Key &key) {
  std::string text;
  llvm::raw_string_ostream os(text);
  os << names.digest(key.carrier);
  for (auto label : key.labels.getAsRange<FlatSymbolRefAttr>())
    os << '\0' << label.getValue();
  return text;
}

} // namespace

// Each key's sum's name. A closure key's is named under `fn$`, a lazy
// key's under `lazy$`, which no Idris name holds; two keys on one name are
// the compiler's error, raised where the name is interned.
LogicalResult Slots::name() {
  ContentNames content;
  for (const Key &key : keys) {
    FailureOr<StringAttr> name = content.intern(program.getLoc(), key.isLazy() ? "lazy$" : "fn$",
                                                "sum", keyText(content, key));
    if (failed(name))
      return failure();
    names[key] = *name;
  }
  return success();
}

unsigned Slots::numConstructors() const {
  unsigned count = 0;
  for (const Key &key : keys)
    count += static_cast<unsigned>(key.labels.size());
  return count;
}

} // namespace idr::defunctionalize
