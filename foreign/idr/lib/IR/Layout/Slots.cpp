// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A data type's words, laid out once while the type is made, over plain
// arrays: the one word of a cell, a frame stack or a number, or the slots
// of a value held in place, whose constructors share the words they can.

#include "idr/IR/Layout/SlotPlan.h"

#include "idr/Support/Match.h"

#include "llvm/ADT/DenseMap.h"

#include <tuple>

using namespace mlir;

namespace idr::families {

namespace {

// A word's shape and kind as a key, so a constructor finds the free words
// of each in one lookup.
using WordKey = std::tuple<unsigned, unsigned, const void *, unsigned>;

WordKey keyOf(const SlotWord &word) {
  auto kind = static_cast<unsigned>(word.kind);
  return match(
      word.shape, [&](PointerWord) { return WordKey{0, 0, nullptr, kind}; },
      [&](IntegerWord integer) { return WordKey{1, integer.bits, nullptr, kind}; },
      [&](ScalarWord scalar) { return WordKey{2, 0, scalar.type.getAsOpaquePointer(), kind}; });
}

// The width of a tag that tells `declared` constructors apart.
unsigned tagBits(uint32_t declared) {
  return declared <= 256 ? 8u : declared <= 65536 ? 16u : 32u;
}

SmallVector<SlotWord> flatOf(std::optional<IntegerWord> tag, ArrayRef<SlotWord> words) {
  SmallVector<SlotWord> out;
  if (tag)
    out.push_back(SlotWord{*tag, layout::Word::Uncounted});
  llvm::append_range(out, words);
  return out;
}

} // namespace

SmallVector<SlotWord> SlotPlan::flat() const { return flatOf(tag, words); }

SmallVector<SlotWord> flatWords(const Slots &slots) { return flatOf(slots.tag, slots.words); }

Slots SlotPlan::keep(StorageUniquer::StorageAllocator &allocator) const {
  SmallVector<ArrayRef<ArrayRef<uint32_t>>> byTag;
  for (const SmallVector<SmallVector<uint32_t>> &perField : fields) {
    SmallVector<ArrayRef<uint32_t>> kept;
    for (const SmallVector<uint32_t> &positions : perField)
      kept.push_back(allocator.copyInto(ArrayRef<uint32_t>(positions)));
    byTag.push_back(allocator.copyInto(ArrayRef<ArrayRef<uint32_t>>(kept)));
  }
  return Slots{tag, allocator.copyInto(ArrayRef<SlotWord>(words)),
               allocator.copyInto(ArrayRef<ArrayRef<ArrayRef<uint32_t>>>(byTag))};
}

SlotPlan oneWord(SlotWord word) { return SlotPlan{std::nullopt, {word}, {}}; }

SlotPlan inPlace(uint32_t declared, ArrayRef<Tag> tags,
                 ArrayRef<SmallVector<SmallVector<SlotWord>>> fields) {
  SlotPlan out;
  if (tags.size() >= 2)
    out.tag = IntegerWord{tagBits(declared)};
  uint32_t first = out.tag ? 1u : 0u;
  out.fields.resize(declared);
  // How many constructors use each word.
  SmallVector<uint32_t> users;
  for (auto [tag, perField] : llvm::zip_equal(tags, fields)) {
    // The free words of each key, in word order: built once per
    // constructor, since searching the words again for every field is
    // quadratic in a wide sum.
    llvm::DenseMap<WordKey, SmallVector<uint32_t>> free;
    llvm::DenseMap<WordKey, uint32_t> cursor;
    for (auto [at, word] : llvm::enumerate(out.words))
      free[keyOf(word)].push_back(first + static_cast<uint32_t>(at));
    SmallVector<SmallVector<uint32_t>> &positions = out.fields[static_cast<uint32_t>(tag)];
    for (const SmallVector<SlotWord> &field : perField) {
      SmallVector<uint32_t> &taken = positions.emplace_back();
      for (const SlotWord &word : field) {
        WordKey key = keyOf(word);
        SmallVector<uint32_t> &bucket = free[key];
        uint32_t &at = cursor[key];
        uint32_t chosen;
        if (at < bucket.size()) {
          chosen = bucket[at++];
        } else {
          chosen = first + static_cast<uint32_t>(out.words.size());
          out.words.push_back(word);
          users.push_back(0);
        }
        ++users[chosen - first];
        taken.push_back(chosen);
      }
    }
  }
  for (auto [word, used] : llvm::zip_equal(out.words, users))
    if (word.kind == layout::Word::Cell && used < tags.size())
      word.kind = layout::Word::MaybeCell;
  return out;
}

} // namespace idr::families
