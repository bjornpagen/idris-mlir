// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The run's arena of patterns and keys: each interned by its structure,
// once, under one lock, so equal patterns and keys are one pointer and a
// request interns its key once, after it is judged.

#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Specialize.h"

#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::specialize {

//===----------------------------------------------------------------------===//
// The arena
//===----------------------------------------------------------------------===//

namespace {

// The kinds of thing the arena interns, each in its own buckets.
enum class Interned : unsigned { Hole, Con, Const, PatternKey, RaiseKey, SignatureKey };

Interned kindOf(const Pattern::Node &node) {
  return idr::match(
      node, [](Hole) { return Interned::Hole; }, [](const Con &) { return Interned::Con; },
      [](const Const &) { return Interned::Const; });
}

llvm::hash_code hashOf(const Pattern::Node &node) {
  return idr::match(
      node, [](Hole) { return llvm::hash_value(0); },
      [](const Con &con) {
        return llvm::hash_combine(static_cast<unsigned>(con.tag),
                                  llvm::hash_combine_range(con.fields.begin(), con.fields.end()));
      },
      [](const Const &constant) { return llvm::hash_value(constant.value.getAsOpaquePointer()); });
}

// Whether two nodes are one: of one kind, a constructor of one tag over the
// same fields, a constant of the same attribute.
bool sameNode(const Pattern::Node &a, const Pattern::Node &b) {
  return idr::match(
      a,
      [&](Hole) {
        return idr::match(b, [](Hole) { return true; }, [](const auto &) { return false; });
      },
      [&](const Con &con) {
        return idr::match(
            b,
            [&](const Con &other) { return con.tag == other.tag && llvm::equal(con.fields, other.fields); },
            [](const auto &) { return false; });
      },
      [&](const Const &constant) {
        return idr::match(
            b, [&](const Const &other) { return constant.value == other.value; },
            [](const auto &) { return false; });
      });
}

} // namespace

llvm::ArrayRef<const Pattern *> Arena::copy(llvm::ArrayRef<const Pattern *> list) {
  auto *at = storage.Allocate<const Pattern *>(list.size());
  llvm::copy(list, at);
  return {at, list.size()};
}

const Pattern *Arena::intern(Pattern::Node node, unsigned holes) {
  std::lock_guard lock(mutex);
  llvm::SmallVector<const void *, 1> &bucket =
      byHash[{static_cast<unsigned>(kindOf(node)), hashOf(node)}];
  for (const void *met : bucket)
    if (sameNode(static_cast<const Pattern *>(met)->get(), node))
      return static_cast<const Pattern *>(met);
  // A constructor's fields are the caller's until copied into the arena.
  Pattern::Node owned = idr::match(
      node, [](Hole hole) -> Pattern::Node { return hole; },
      [&](const Con &con) -> Pattern::Node { return Con{con.tag, copy(con.fields)}; },
      [](const Const &constant) -> Pattern::Node { return constant; });
  auto *made = new (storage.Allocate<Pattern>()) Pattern(owned);
  made->holeCount = holes;
  bucket.push_back(made);
  return made;
}

const Pattern *Arena::hole() { return intern(Hole{}, 1); }

const Pattern *Arena::con(Tag tag, llvm::ArrayRef<const Pattern *> fields) {
  unsigned holes = 0;
  for (const Pattern *field : fields)
    holes += field->holes();
  return intern(Con{tag, fields}, holes);
}

const Pattern *Arena::constant(Attribute value) { return intern(Const{value}, 0); }

const PatternKey *Arena::key(FunctionId owner, llvm::ArrayRef<const Pattern *> params) {
  std::lock_guard lock(mutex);
  llvm::hash_code hash =
      llvm::hash_combine(owner.index(), llvm::hash_combine_range(params.begin(), params.end()));
  llvm::SmallVector<const void *, 1> &bucket =
      byHash[{static_cast<unsigned>(Interned::PatternKey), hash}];
  for (const void *met : bucket) {
    const auto *key = static_cast<const PatternKey *>(met);
    if (key->owner == owner && llvm::equal(key->params, params))
      return key;
  }
  auto *made = new (storage.Allocate<PatternKey>()) PatternKey{owner, copy(params)};
  bucket.push_back(made);
  return made;
}

const RaiseKey *Arena::key(FunctionId callee, FormId form) {
  std::lock_guard lock(mutex);
  llvm::hash_code hash = llvm::hash_combine(callee.index(), static_cast<unsigned>(form));
  llvm::SmallVector<const void *, 1> &bucket =
      byHash[{static_cast<unsigned>(Interned::RaiseKey), hash}];
  for (const void *met : bucket) {
    const auto *key = static_cast<const RaiseKey *>(met);
    if (key->callee == callee && key->form == form)
      return key;
  }
  auto *made = new (storage.Allocate<RaiseKey>()) RaiseKey{callee, form};
  bucket.push_back(made);
  return made;
}

const SignatureKey *Arena::key(FunctionId owner, FunctionType signature,
                               IndexArgsAttr indices) {
  std::lock_guard lock(mutex);
  llvm::hash_code hash = llvm::hash_combine(owner.index(), signature, indices);
  llvm::SmallVector<const void *, 1> &bucket =
      byHash[{static_cast<unsigned>(Interned::SignatureKey), hash}];
  for (const void *met : bucket) {
    const auto *key = static_cast<const SignatureKey *>(met);
    if (key->owner == owner && key->signature == signature && key->indices == indices)
      return key;
  }
  auto *made = new (storage.Allocate<SignatureKey>()) SignatureKey{owner, signature, indices};
  bucket.push_back(made);
  return made;
}

unsigned PatternKey::holes() const {
  unsigned total = 0;
  for (const Pattern *param : params)
    total += param->holes();
  return total;
}

} // namespace idr::specialize
