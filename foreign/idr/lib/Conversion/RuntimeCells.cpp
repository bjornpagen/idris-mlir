// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A cell as compiled code reads and writes it: its header (the count, then
// the info word, where the target's data layout puts them), the words
// after the header it holds of itself (Cell's own words, written as its
// layout gives them), and the slots of its components.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/Conversion/Runtime.h"
#include "idr/Conversion/Words.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"

#include <optional>

using namespace mlir;

namespace idr::conversion {

namespace {

// Whether a load of what stays carries LLVM's invariant group.
bool invariantGroup(Contents stays) { return stays == Contents::Stays; }

} // namespace

// The runtime writes the header of a counted cell as it allocates it.
Value Runtime::allocate(OpBuilder &b, Location loc, const layout::Cell &cell) const {
  Value size = i64Constant(b, loc, cell.size), info = i32Constant(b, loc, cell.info.word());
  Value address = call(b, loc, idr::runtime::helper::cell, ValueRange{size, info}).getResult();
  storeCellWords(b, loc, address, cell);
  return address;
}

void Runtime::storeUncountedHeader(OpBuilder &b, Location loc, Value address,
                                   const layout::Cell &cell) const {
  LLVM::StoreOp::create(b, loc, i32Constant(b, loc, 0), at(b, loc, address, headerLayout.countAt),
                        alignAt(cellAlignment(), headerLayout.countAt));
  storeInfoAndWords(b, loc, address, cell);
}

void Runtime::storeInfoAndWords(OpBuilder &b, Location loc, Value address,
                                const layout::Cell &cell) const {
  storeInfo(b, loc, address, i32Constant(b, loc, cell.info.word()));
  storeCellWords(b, loc, address, cell);
}

void Runtime::storeCellWords(OpBuilder &b, Location loc, Value address,
                             const layout::Cell &cell) const {
  for (const layout::OwnWord &word : cell.words)
    LLVM::StoreOp::create(b, loc, LLVM::ConstantOp::create(b, loc, word.type, word.value),
                          at(b, loc, address, word.offset), alignAt(cellAlignment(), word.offset));
}

Value Runtime::loadTag(OpBuilder &b, Location loc, Value cell, DataType data,
                       Contents stays) const {
  Type i64 = b.getI64Type();
  Value info = LLVM::LoadOp::create(b, loc, b.getI32Type(), at(b, loc, cell, headerLayout.infoAt),
                                    alignAt(cellAlignment(), headerLayout.infoAt),
                                    /*isVolatile=*/false, /*isNonTemporal=*/false,
                                    /*isInvariant=*/false, invariantGroup(stays));
  Value inGroup = LLVM::AndOp::create(b, loc, info, i32Constant(b, loc, layout::tagMask));
  Value tag = LLVM::ZExtOp::create(b, loc, i64, inGroup);
  // A sum of more constructors than a header's tag holds keeps the rest of
  // the tag in its group word, at one offset in every cell of the sum, so
  // it is read before the constructor is known: two layouts of a tag,
  // which the runtime's header field decides.
  std::optional<unsigned> group = layouts.cells(data).group;
  if (!group)
    return tag;
  Value word = LLVM::LoadOp::create(b, loc, i64, at(b, loc, cell, *group),
                                    alignAt(cellAlignment(), *group), /*isVolatile=*/false,
                                    /*isNonTemporal=*/false, /*isInvariant=*/false,
                                    invariantGroup(stays));
  return LLVM::AddOp::create(b, loc, groupBase(b, loc, word), tag);
}

Value Runtime::loadInfo(OpBuilder &b, Location loc, Value cell) const {
  return LLVM::LoadOp::create(b, loc, b.getI32Type(), at(b, loc, cell, headerLayout.infoAt),
                              alignAt(cellAlignment(), headerLayout.infoAt));
}

void Runtime::storeInfo(OpBuilder &b, Location loc, Value cell, Value info) const {
  LLVM::StoreOp::create(b, loc, info, at(b, loc, cell, headerLayout.infoAt),
                        alignAt(cellAlignment(), headerLayout.infoAt));
}

void Runtime::store(OpBuilder &b, Location loc, Value address, unsigned align,
                    ArrayRef<layout::Slot> slots, ValueRange values) const {
  for (auto [slot, value] : llvm::zip_equal(slots, values))
    LLVM::StoreOp::create(b, loc, value, at(b, loc, address, slot.offset),
                          alignAt(align, slot.offset));
}

SmallVector<Value> Runtime::load(OpBuilder &b, Location loc, Value address, unsigned align,
                                 ArrayRef<layout::Slot> slots, Contents stays) const {
  SmallVector<Value> values;
  for (const layout::Slot &slot : slots)
    values.push_back(LLVM::LoadOp::create(b, loc, slot.type, at(b, loc, address, slot.offset),
                                          alignAt(align, slot.offset), /*isVolatile=*/false,
                                          /*isNonTemporal=*/false, /*isInvariant=*/false,
                                          invariantGroup(stays)));
  return values;
}

void Runtime::storeWord(OpBuilder &b, Location loc, Value address, Value value) const {
  LLVM::StoreOp::create(b, loc, value, address, cellAlignment());
}

Value Runtime::launder(OpBuilder &b, Location loc, Value cell) const {
  return LLVM::LaunderInvariantGroupOp::create(b, loc, cell.getType(), cell);
}

} // namespace idr::conversion
