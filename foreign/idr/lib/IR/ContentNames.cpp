// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The digest of an attribute or a type that no process, address or printing
// flag reaches: XXH3-128 of what its dialect's bytecode writes of it, each
// attribute or type it holds written as that one's own digest.
//
// The bytecode encoding is MLIR's own process-independent account of an
// attribute's content, one per dialect (builtin's, and ours, which the
// specification generates); a TypeID or a storage address differs from run
// to run, and a printed form is what a printing flag changes. A hashing
// writer stands where the bytecode writer would: it writes nothing, so a
// digest costs one pass over the content.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"

#include "mlir/Bytecode/BytecodeImplementation.h"
#include "mlir/Bytecode/Encoding.h"
#include "mlir/IR/Dialect.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/Twine.h"
#include "llvm/Support/Endian.h"
#include "llvm/Support/ErrorHandling.h"

using namespace mlir;
using namespace idr;

namespace {

// An attribute or a type: one entry the bytecode writes. The two storages
// are distinct objects, so their addresses key one table of this digest's
// own scratch.
enum class Kind : uint8_t { Attribute, Type };

struct Entry {
  Kind kind;
  const void *impl;
};

using Digests = llvm::DenseMap<const void *, llvm::XXH128_hash_t>;

// What precedes each part in the stream, so no two different contents
// write the same bytes: a string's bytes and an entry's digest are told
// apart by their marks, and a string carries its length.
enum class Mark : uint8_t { Word, Bytes, Entry, Absent, Dialect };

// A writer that keeps what the bytecode would write as bytes to digest: a
// word in eight little-endian bytes, whatever the host. An entry it holds
// is written as its digest, found among those already made; one not yet
// made is noted, and the digest of what holds it waits for it.
class Hasher final : public DialectBytecodeWriter {
public:
  Hasher(const Digests &done, SmallVectorImpl<Entry> &missing) : done(done), missing(missing) {}

  // Writes `entry` as its dialect's bytecode does, preceded by its kind
  // and its dialect's namespace, the two the dialect's own encoding leaves
  // to the bytecode around it.
  void encode(Entry entry) {
    mark(Mark::Dialect);
    word(static_cast<uint64_t>(entry.kind));
    Dialect *dialect = nullptr;
    LogicalResult written = failure();
    switch (entry.kind) {
    case Kind::Attribute: {
      Attribute attr = Attribute::getFromOpaquePointer(entry.impl);
      dialect = &attr.getDialect();
      bytes(dialect->getNamespace());
      if (auto *iface = dialect->getRegisteredInterface<BytecodeDialectInterface>())
        written = iface->writeAttribute(attr, *this);
      break;
    }
    case Kind::Type: {
      Type type = Type::getFromOpaquePointer(entry.impl);
      dialect = &type.getDialect();
      bytes(dialect->getNamespace());
      if (auto *iface = dialect->getRegisteredInterface<BytecodeDialectInterface>())
        written = iface->writeType(type, *this);
      break;
    }
    }
    // Every attribute and type the compiler keys a copy by is of a dialect
    // whose bytecode writes it; one that is not has no content to digest
    // short of its printed form, which is no digest of content.
    if (failed(written))
      llvm::reportFatalInternalError(llvm::Twine("a digest of content meets an ") +
                                     (entry.kind == Kind::Attribute ? "attribute" : "type") +
                                     " of dialect '" + dialect->getNamespace() +
                                     "' its bytecode does not write");
  }

  llvm::XXH128_hash_t finish() const { return llvm::xxh3_128bits(stream.data(), stream.size()); }

  void writeAttribute(Attribute attr) override {
    entry(Entry{Kind::Attribute, attr.getAsOpaquePointer()});
  }
  void writeOptionalAttribute(Attribute attr) override {
    if (!attr) {
      mark(Mark::Absent);
      return;
    }
    writeAttribute(attr);
  }
  void writeType(Type type) override { entry(Entry{Kind::Type, type.getAsOpaquePointer()}); }

  // A resource's bytes live outside the attribute that names it, keyed by
  // a name the context chose; the compiler keys no copy by one.
  void writeResourceHandle(const AsmDialectResourceHandle &) override {
    llvm::reportFatalInternalError("a digest of content meets a dialect resource, whose bytes "
                                   "are outside the attribute");
  }

  void writeVarInt(uint64_t value) override { word(value); }
  void writeSignedVarInt(int64_t value) override { word(static_cast<uint64_t>(value)); }
  void writeAPIntWithKnownWidth(const APInt &value) override {
    word(value.getBitWidth());
    for (unsigned i = 0, n = value.getNumWords(); i < n; ++i)
      word(value.getRawData()[i]);
  }
  void writeAPFloatWithKnownSemantics(const APFloat &value) override {
    writeAPIntWithKnownWidth(value.bitcastToAPInt());
  }
  void writeOwnedString(StringRef str) override { bytes(str); }
  void writeOwnedBlob(ArrayRef<char> blob) override {
    bytes(StringRef(blob.data(), blob.size()));
  }
  void writeUnownedBlob(ArrayRef<char> blob) override {
    bytes(StringRef(blob.data(), blob.size()));
  }
  void writeOwnedBool(bool value) override { word(value ? 1 : 0); }

  // The current encoding, which every dialect's writer reads to choose its
  // form; no dialect version is pinned, so each writes its newest.
  int64_t getBytecodeVersion() const override { return bytecode::kVersion; }
  FailureOr<const DialectVersion *> getDialectVersion(StringRef) const override {
    return failure();
  }

private:
  void mark(Mark m) { stream.push_back(static_cast<uint8_t>(m)); }
  void word(uint64_t value) {
    mark(Mark::Word);
    uint8_t out[8];
    llvm::support::endian::write64le(out, value);
    stream.append(std::begin(out), std::end(out));
  }
  void bytes(StringRef text) {
    mark(Mark::Bytes);
    word(text.size());
    stream.append(text.bytes_begin(), text.bytes_end());
  }
  void entry(Entry e) {
    mark(Mark::Entry);
    auto it = done.find(e.impl);
    if (it == done.end()) {
      missing.push_back(e);
      return;
    }
    word(it->second.low64);
    word(it->second.high64);
  }

  const Digests &done;
  SmallVectorImpl<Entry> &missing;
  SmallVector<uint8_t, 256> stream;
};

// The digest of `root`, every entry it holds digested first. No step
// recurses on the nesting: an entry whose parts are not yet digested goes
// back on the stack beneath them, so each is encoded at most twice.
llvm::XXH128_hash_t digestOf(Entry root) {
  Digests done;
  SmallVector<Entry> stack{root};
  SmallVector<Entry> missing;
  while (!stack.empty()) {
    Entry top = stack.back();
    if (done.contains(top.impl)) {
      stack.pop_back();
      continue;
    }
    missing.clear();
    Hasher hasher(done, missing);
    hasher.encode(top);
    if (!missing.empty()) {
      stack.append(missing);
      continue;
    }
    done[top.impl] = hasher.finish();
    stack.pop_back();
  }
  return done.lookup(root.impl);
}

} // namespace

// No attribute (an op with no properties) has one digest of its own, which
// no attribute's stream writes: a lone absent mark.
llvm::XXH128_hash_t idr::stableDigest(Attribute attr) {
  if (!attr) {
    const uint8_t absent = static_cast<uint8_t>(Mark::Absent);
    return llvm::xxh3_128bits(&absent, 1);
  }
  return digestOf(Entry{Kind::Attribute, attr.getAsOpaquePointer()});
}

llvm::XXH128_hash_t idr::stableDigest(Type type) {
  return digestOf(Entry{Kind::Type, type.getAsOpaquePointer()});
}
