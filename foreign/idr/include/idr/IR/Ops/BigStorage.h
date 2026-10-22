// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The storage of #idr.big: its key is the integer at its fewest signed bits,
// whatever width a caller, the parser or the bytecode reader gives it at.
// The uniquer derives the key before it hashes or compares, so equal
// integers are one attribute and no reader compares widths.
#ifndef IDR_IR_OPS_BIGSTORAGE_H
#define IDR_IR_OPS_BIGSTORAGE_H

#include "mlir/IR/AttributeSupport.h"
#include "llvm/ADT/APInt.h"
#include "llvm/ADT/Hashing.h"

#include <utility>

namespace idr::detail {

struct BigAttrStorage : mlir::AttributeStorage {
  using KeyTy = llvm::APInt;

  explicit BigAttrStorage(llvm::APInt value) : value(std::move(value)) {}

  static KeyTy getKey(const llvm::APInt &value) {
    return value.sextOrTrunc(value.getSignificantBits());
  }

  // Two keys of one integer are of one width, so this is equality of
  // integers.
  bool operator==(const KeyTy &key) const { return llvm::APInt::isSameValue(value, key); }

  static llvm::hash_code hashKey(const KeyTy &key) { return llvm::hash_value(key); }

  static BigAttrStorage *construct(mlir::AttributeStorageAllocator &allocator, KeyTy &&key) {
    return new (allocator.allocate<BigAttrStorage>()) BigAttrStorage(std::move(key));
  }

  llvm::APInt value;
};

} // namespace idr::detail

#endif // IDR_IR_OPS_BIGSTORAGE_H
