// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The names generated from content, which no creation order reaches, and
// the canonical text and hash every content key is made of, which no
// printing flag reaches.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"

#include "mlir/IR/AsmState.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/OwningOpRef.h"
#include "llvm/ADT/StringExtras.h"
#include "llvm/Support/Format.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/Support/xxhash.h"

#include <limits>

using namespace mlir;
using namespace idr;

//===----------------------------------------------------------------------===//
// Names from content
//===----------------------------------------------------------------------===//

raw_ostream &idr::operator<<(raw_ostream &os, Digest digest) {
  return os << llvm::format_hex_no_prefix(digest.high, 16, /*Upper=*/false)
            << llvm::format_hex_no_prefix(digest.low, 16, /*Upper=*/false);
}

Digest idr::digestOf(StringRef key) {
  llvm::XXH128_hash_t hash = llvm::xxh3_128bits(llvm::arrayRefFromStringRef(key));
  return {hash.low64, hash.high64};
}

std::string idr::contentHash(StringRef key) {
  std::string text;
  llvm::raw_string_ostream os(text);
  os << llvm::format_hex_no_prefix(digestOf(key).low, 16, /*Upper=*/false);
  return text;
}

std::string idr::contentName(StringRef owner, StringRef kind, Digest key) {
  std::string name;
  llvm::raw_string_ostream os(name);
  os << owner << '.' << kind << '.' << llvm::format_hex_no_prefix(key.low, 16, /*Upper=*/false);
  return name;
}

std::string idr::contentName(StringRef owner, StringRef kind, StringRef key) {
  return contentName(owner, kind, digestOf(key));
}

FailureOr<StringAttr> ContentNames::intern(Location at, StringRef owner, StringRef kind,
                                           Digest key) {
  std::string name = contentName(owner, kind, key);
  auto [it, fresh] = keys.try_emplace(name, key);
  if (!fresh && it->second != key) {
    std::string both;
    llvm::raw_string_ostream(both) << it->second << " and " << key;
    return emitError(at) << "internal error: two keys name " << name
                         << ": the keys of digest " << both;
  }
  return StringAttr::get(at->getContext(), name);
}

//===----------------------------------------------------------------------===//
// Canonical text
//===----------------------------------------------------------------------===//

namespace {

// Every option of the printer, chosen here: OpPrintingFlags' own
// constructor reads the command line's.
OpPrintingFlags canonicalFlags() {
  OpPrintingFlags flags;
  flags.elideLargeElementsAttrs(std::numeric_limits<int64_t>::max())
      .printLargeElementsAttrWithHex(100)
      .elideLargeResourceString(std::numeric_limits<int64_t>::max())
      .enableDebugInfo(/*enable=*/false, /*prettyForm=*/false)
      .printGenericOpForm(true)
      .skipRegions(false)
      .assumeVerified(true)
      .useLocalScope(false)
      .printValueUsers(false)
      .printUniqueSSAIDs(false)
      .printNameLocAsPrefix(false);
  return flags;
}

// `op` printed whole: detached, it is printed as the top of its own text,
// its aliases first; inside another op, numbered from itself.
std::string printed(Operation *op) {
  std::string text;
  llvm::raw_string_ostream os(text);
  AsmState state(op, canonicalFlags());
  op->print(os, state);
  return text;
}

// An attribute held by a detached op of its own, so that it is printed with
// the aliases of its text written before it.
std::string heldAlone(Attribute attr) {
  OwningOpRef<ModuleOp> holder = ModuleOp::create(UnknownLoc::get(attr.getContext()));
  holder->getOperation()->setAttr("idr.key", attr);
  return printed(holder->getOperation());
}

} // namespace

std::string idr::canonicalText(Attribute attr) { return heldAlone(attr); }
std::string idr::canonicalText(Type type) { return heldAlone(TypeAttr::get(type)); }
std::string idr::canonicalText(Operation *op) { return printed(op); }

Digest idr::canonicalHash(Attribute attr) { return digestOf(canonicalText(attr)); }
Digest idr::canonicalHash(Type type) { return digestOf(canonicalText(type)); }
Digest idr::canonicalHash(Operation *op) { return digestOf(canonicalText(op)); }

Digest ContentNames::digest(Attribute attr) {
  auto [it, fresh] = digests.try_emplace(attr.getAsOpaquePointer());
  if (fresh)
    it->second = canonicalHash(attr);
  return it->second;
}

Digest ContentNames::digest(Type type) {
  auto [it, fresh] = digests.try_emplace(type.getAsOpaquePointer());
  if (fresh)
    it->second = canonicalHash(type);
  return it->second;
}
