// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a static datum is named: a reserved name (reservedName), so no name
// of the program's or the runtime's is one, made from the digest of its
// content, which names everything the datum points at by that thing's own
// name, so that two constants of one content are one global whatever wrote
// them, and no order of writing reaches a name. An attribute or a type is
// digested from its canonical text, which no printing flag reaches and
// which is printed once for each type, however many data hold it.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"
#include "idr/Conversion/StaticData.h"

#include "llvm/ADT/StringExtras.h"
#include "llvm/Support/raw_ostream.h"

using namespace mlir;

namespace idr::conversion {

StaticData::Named StaticData::intern(Location loc, StringRef kind, Digest key) {
  std::string name = reservedName(kind, key);
  collision = collision || failed(names.intern(loc, name, key));
  return {std::move(name), key};
}

Digest StaticData::cellKey(Type type, const Ctor &ctor, ArrayRef<std::string> fields) {
  std::string typeKey;
  llvm::raw_string_ostream(typeKey) << names.digest(type);
  return digestOf(typeKey + " " + ctor.name.getValue().str() + "(" + llvm::join(fields, ", ") +
                  ")");
}

// A static memo cell is one per value, as a force needs: it would otherwise
// run and store the same value twice. A memo sum's every state is a memo
// cell.
StringRef StaticData::kindOf(DataType data) { return data.isMemo() ? "caf" : "box"; }

} // namespace idr::conversion
