// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A cell as compiled code reads and writes it: its header (the count, then
// the info word), the words after the header its layout has (the count of
// its object slots where the header cannot hold it, its constructor's group
// in a sum of more constructors than a header's tag holds), and the slots
// of its components.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/Conversion/Runtime.h"
#include "idr/Conversion/Words.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"

// The runtime's C ABI: a cell's header and the size of a word.
#include "idris_rt.h"

#include <optional>

using namespace mlir;

namespace idr::conversion {

Value Runtime::allocate(OpBuilder &b, Location loc, const layout::Cell &cell, Tag tag) {
  Value size = i64Constant(b, loc, cell.size), info = i32Constant(b, loc, cell.info.word());
  Value address = call(b, loc, "idris_rt_cell", ptrType(b.getContext()), ValueRange{size, info});
  storeCellWords(b, loc, address, cell, tag);
  return address;
}

void Runtime::storeHeader(OpBuilder &b, Location loc, Value address, const layout::Cell &cell,
                          Tag tag, layout::CellInfo info) {
  LLVM::StoreOp::create(b, loc, i32Constant(b, loc, 1), address, alignAt(cellAlignment(), 0));
  storeInfo(b, loc, address, i32Constant(b, loc, info.word()));
  storeCellWords(b, loc, address, cell, tag);
}

void Runtime::storeCellWords(OpBuilder &b, Location loc, Value address, const layout::Cell &cell,
                             Tag tag) {
  constexpr unsigned after = sizeof(idris_rt_header);
  if (cell.countWord())
    LLVM::StoreOp::create(b, loc, i64Constant(b, loc, cell.objs), at(b, loc, address, after),
                          alignAt(cellAlignment(), after));
  if (cell.group)
    LLVM::StoreOp::create(b, loc,
                          LLVM::ConstantOp::create(b, loc, cell.group->type, groupWord(tag)),
                          at(b, loc, address, cell.group->offset),
                          alignAt(cellAlignment(), cell.group->offset));
}

Value Runtime::loadTag(OpBuilder &b, Location loc, Value cell, DataType data,
                       const Layouts &layouts) {
  Type i64 = b.getI64Type();
  Value inGroup = LLVM::AndOp::create(b, loc, loadInfo(b, loc, cell),
                                      i32Constant(b, loc, layout::tagMask));
  Value tag = LLVM::ZExtOp::create(b, loc, i64, inGroup);
  // Every cell of a sum with groups has the group word at one offset, so it
  // is read before the constructor is known.
  std::optional<layout::Slot> group =
      data.getCtors().empty() ? std::nullopt : layouts.box(data, Tag{0}).group;
  if (!group)
    return tag;
  Value word = LLVM::LoadOp::create(b, loc, group->type, at(b, loc, cell, group->offset),
                                    alignAt(cellAlignment(), group->offset));
  return LLVM::AddOp::create(b, loc, groupBase(b, loc, word), tag);
}

Value Runtime::loadInfo(OpBuilder &b, Location loc, Value cell) {
  return LLVM::LoadOp::create(b, loc, b.getI32Type(), at(b, loc, cell, 4),
                              alignAt(cellAlignment(), 4));
}

void Runtime::storeInfo(OpBuilder &b, Location loc, Value cell, Value info) {
  LLVM::StoreOp::create(b, loc, info, at(b, loc, cell, 4), alignAt(cellAlignment(), 4));
}

void Runtime::store(OpBuilder &b, Location loc, Value address, unsigned align,
                    ArrayRef<layout::Slot> slots, ValueRange values) {
  for (auto [slot, value] : llvm::zip_equal(slots, values))
    LLVM::StoreOp::create(b, loc, value, at(b, loc, address, slot.offset),
                          alignAt(align, slot.offset));
}

SmallVector<Value> Runtime::load(OpBuilder &b, Location loc, Value address, unsigned align,
                                 ArrayRef<layout::Slot> slots) {
  SmallVector<Value> values;
  for (const layout::Slot &slot : slots)
    values.push_back(LLVM::LoadOp::create(b, loc, slot.type, at(b, loc, address, slot.offset),
                                          alignAt(align, slot.offset)));
  return values;
}

void Runtime::storeWord(OpBuilder &b, Location loc, Value address, Value value) {
  LLVM::StoreOp::create(b, loc, value, address, IDRIS_RT_WORD_BYTES);
}

Value Runtime::exclusive(OpBuilder &b, Location loc, Value cell) {
  return call(b, loc, "idris_rt_is_unique", b.getI1Type(), cell);
}

} // namespace idr::conversion
