// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a static datum is named: a reserved name (reservedName), so no name
// of the program's (each under the program's prefix) or the runtime's (a C
// identifier, with no `$`) is one, made from the digest of its content, so
// idr-lower-statics and the lowering reach one global by one function of
// the constant they both hold, and no order of making reaches a name.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"
#include "idr/Conversion/StaticData.h"

#include "llvm/Support/raw_ostream.h"

using namespace mlir;

namespace idr::conversion {

std::string StaticNames::string(StringRef bytes) { return reservedName("str", digestOf(bytes)); }

std::string StaticNames::big(BigAttr value) { return reservedName("big", canonicalHash(value)); }

// A memo cell is one per value, as a force needs (it would otherwise run
// and store the same value twice), and of a kind of its own, written once.
// A spine run's later cells are named from the run's constant and the
// cell's place in it, so a run of any length names each cell in one step.
std::string StaticNames::cell(ConAttr con, unsigned k) {
  StringRef kind = con.getData().memo() ? "caf" : "cell";
  if (k == 0)
    return reservedName(kind, canonicalHash(con));
  std::string key;
  llvm::raw_string_ostream(key) << canonicalHash(con) << "+" << k;
  return reservedName(kind, digestOf(key));
}

// A constant array's name is its value's and type's canonical digests, so a
// large constant is printed once.
std::string StaticNames::array(memref::GlobalOp global) {
  std::string key;
  llvm::raw_string_ostream(key) << canonicalHash(Attribute(*global.getInitialValue())) << " : "
                                << canonicalHash(Type(global.getType()));
  return reservedName("array", digestOf(key));
}

std::string StaticNames::nothing() { return reservedName("nothing", "cell"); }

std::string StaticNames::text(StringRef bytes) { return reservedName("text", digestOf(bytes)); }

std::string StaticNames::homes() { return reservedName("homes", "cursors"); }

Value staticAddress(OpBuilder &b, Location loc, StringRef name) {
  return LLVM::AddressOfOp::create(b, loc, LLVM::LLVMPointerType::get(b.getContext()), name);
}

} // namespace idr::conversion
