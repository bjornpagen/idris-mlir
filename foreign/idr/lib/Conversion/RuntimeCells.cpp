// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A cell as compiled code reads and writes it: its header (the count, then
// the info word), the words after the header it holds of itself (Cell's
// own words, written as its layout gives them), and the slots of its
// components.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/Conversion/Runtime.h"
#include "idr/Conversion/Words.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"

// The runtime's C ABI: a cell's header and the size of a word.
#include "idris_rt.h"

#include <cstddef>
#include <optional>

using namespace mlir;

namespace idr::conversion {

namespace {

// Where the header's two words are.
constexpr auto countAt = static_cast<unsigned>(offsetof(idris_rt_header, count));
constexpr auto infoAt = static_cast<unsigned>(offsetof(idris_rt_header, info));

} // namespace

Value Runtime::allocate(OpBuilder &b, Location loc, const layout::Cell &cell) {
  Value size = i64Constant(b, loc, cell.size), info = i32Constant(b, loc, cell.info.word());
  Value address = call(b, loc, idr::runtime::helper::cell, ValueRange{size, info}).getResult();
  storeCellWords(b, loc, address, cell);
  return address;
}

void Runtime::storeHeader(OpBuilder &b, Location loc, Value address, const layout::Cell &cell,
                          layout::CellInfo info) {
  LLVM::StoreOp::create(b, loc, i32Constant(b, loc, 1), at(b, loc, address, countAt),
                        alignAt(cellAlignment(), countAt));
  storeInfo(b, loc, address, i32Constant(b, loc, info.word()));
  storeCellWords(b, loc, address, cell);
}

void Runtime::storeCellWords(OpBuilder &b, Location loc, Value address, const layout::Cell &cell) {
  for (const layout::OwnWord &word : cell.words)
    LLVM::StoreOp::create(b, loc, LLVM::ConstantOp::create(b, loc, word.type, word.value),
                          at(b, loc, address, word.offset), alignAt(cellAlignment(), word.offset));
}

Value Runtime::loadTag(OpBuilder &b, Location loc, Value cell, DataType data,
                       const Layouts &layouts) {
  Type i64 = b.getI64Type();
  Value inGroup = LLVM::AndOp::create(b, loc, loadInfo(b, loc, cell),
                                      i32Constant(b, loc, layout::tagMask));
  Value tag = LLVM::ZExtOp::create(b, loc, i64, inGroup);
  // A sum of more constructors than a header's tag holds keeps the rest of
  // the tag in its group word, at one offset in every cell of the sum, so
  // it is read before the constructor is known: two layouts of a tag,
  // which the runtime's header field decides.
  std::optional<unsigned> group = layouts.box(data).group;
  if (!group)
    return tag;
  Value word = LLVM::LoadOp::create(b, loc, i64, at(b, loc, cell, *group),
                                    alignAt(cellAlignment(), *group));
  return LLVM::AddOp::create(b, loc, groupBase(b, loc, word), tag);
}

Value Runtime::loadInfo(OpBuilder &b, Location loc, Value cell) {
  return LLVM::LoadOp::create(b, loc, b.getI32Type(), at(b, loc, cell, infoAt),
                              alignAt(cellAlignment(), infoAt));
}

void Runtime::storeInfo(OpBuilder &b, Location loc, Value cell, Value info) {
  LLVM::StoreOp::create(b, loc, info, at(b, loc, cell, infoAt), alignAt(cellAlignment(), infoAt));
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
  return call(b, loc, idr::runtime::helper::isUnique, cell).getResult();
}

} // namespace idr::conversion
