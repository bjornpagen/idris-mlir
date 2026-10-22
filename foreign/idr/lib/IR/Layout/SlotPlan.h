// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A data type's words while the type is being made: owned, so the class
// rule's unfolding hands a nested application's words to the application
// that holds it, and kept in the type's storage once the type is made. The
// one place two constructors of a value held in place share a word, so the
// count every reader takes is the slots' own.
#ifndef IDR_LIB_IR_LAYOUT_SLOTPLAN_H
#define IDR_LIB_IR_LAYOUT_SLOTPLAN_H

#include "idr/IR/Families/Families.h"

#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/SmallVector.h"

#include <optional>

namespace idr::families {

struct SlotPlan {
  std::optional<IntegerWord> tag;
  llvm::SmallVector<SlotWord> words;
  // By declared tag, then field: each field's words, as positions among all
  // of them, the tag's included.
  llvm::SmallVector<llvm::SmallVector<llvm::SmallVector<uint32_t>>> fields;

  // Every word in order, the tag's first.
  llvm::SmallVector<SlotWord> flat() const;
  // The plan, its arrays copied into `allocator`.
  Slots keep(mlir::StorageUniquer::StorageAllocator &allocator) const;
};

// A value held as the one word `word`.
SlotPlan oneWord(SlotWord word);

// A value held in place over the constructors `tags` of `declared`, the
// fields of the constructor `tags[i]` taking the words `fields[i]`, each
// field's in order: the tag first where `tags` has two constructors or
// more, at the width `declared` needs; then each constructor's fields,
// each component taking the first word before it of its shape and kind
// that no field of the same constructor took, else a new one. A pointer
// some constructor leaves empty is null there: it may be null.
SlotPlan inPlace(uint32_t declared, llvm::ArrayRef<Tag> tags,
                 llvm::ArrayRef<llvm::SmallVector<llvm::SmallVector<SlotWord>>> fields);

// Every word of `slots` in order, the tag's first.
llvm::SmallVector<SlotWord> flatWords(const Slots &slots);

} // namespace idr::families

#endif // IDR_LIB_IR_LAYOUT_SLOTPLAN_H
