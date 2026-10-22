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

#include "llvm/ADT/ArrayRef.h"
#include "llvm/Support/Format.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/Support/xxhash.h"

#include <array>
#include <cstring>

using namespace mlir;

namespace idr::conversion {

namespace {

// A digest as a name's discriminator: 32 lower-case hex digits, the high
// half first.
std::string written(llvm::XXH128_hash_t digest) {
  std::string text;
  llvm::raw_string_ostream(text) << llvm::format_hex_no_prefix(digest.high64, 16)
                                 << llvm::format_hex_no_prefix(digest.low64, 16);
  return text;
}

// The digest of bytes the datum holds as they are: a string's, a text's.
llvm::XXH128_hash_t digestOf(StringRef bytes) {
  return llvm::xxh3_128bits(reinterpret_cast<const uint8_t *>(bytes.data()), bytes.size());
}

// The digest of two digests in order: what a datum made of two contents
// is named by.
llvm::XXH128_hash_t digestOf(llvm::XXH128_hash_t first, llvm::XXH128_hash_t second) {
  std::array<uint64_t, 4> halves{first.high64, first.low64, second.high64, second.low64};
  std::array<uint8_t, sizeof(halves)> bytes;
  std::memcpy(bytes.data(), halves.data(), bytes.size());
  return llvm::xxh3_128bits(bytes.data(), bytes.size());
}

} // namespace

std::string StaticNames::string(StringRef bytes) {
  return reservedName("str", written(digestOf(bytes)));
}

std::string StaticNames::big(BigAttr value) {
  return reservedName("big", written(stableDigest(Attribute(value))));
}

// The cells after a run's first are named by the run's digest and their
// place in it.
std::string StaticNames::cell(ConAttr con, unsigned k) {
  StringRef kind = con.getData().memo() ? "caf" : "cell";
  std::string name = written(stableDigest(Attribute(con)));
  if (k != 0)
    name += "_" + std::to_string(k);
  return reservedName(kind, name);
}

std::string StaticNames::array(memref::GlobalOp global) {
  return reservedName("array", written(digestOf(stableDigest(*global.getInitialValue()),
                                                stableDigest(Type(global.getType())))));
}

std::string StaticNames::nothing() { return reservedName("nothing", "cell"); }

std::string StaticNames::text(StringRef bytes) {
  return reservedName("text", written(digestOf(bytes)));
}

std::string StaticNames::homes() { return reservedName("homes", "cursors"); }

Value staticAddress(OpBuilder &b, Location loc, StringRef name) {
  return LLVM::AddressOfOp::create(b, loc, LLVM::LLVMPointerType::get(b.getContext()), name);
}

} // namespace idr::conversion
