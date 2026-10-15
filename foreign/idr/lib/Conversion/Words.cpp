// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The words idr-lower builds cells, static data and patterns from.

#include "idr/IR/IdrDialect.h"
#include "idr/Conversion/Words.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/Support/MathExtras.h"

#include <optional>

#include "idris_rt.h"

using namespace mlir;

namespace idr::conversion {

Type ptrType(MLIRContext *ctx) { return LLVM::LLVMPointerType::get(ctx); }

Value i64Constant(OpBuilder &b, Location loc, int64_t value) {
  return LLVM::ConstantOp::create(b, loc, b.getI64Type(), value);
}

Value i32Constant(OpBuilder &b, Location loc, int64_t value) {
  return LLVM::ConstantOp::create(b, loc, b.getI32Type(), value);
}

int64_t groupWord(Tag tag) {
  return static_cast<int64_t>(static_cast<uint32_t>(tag) / IDRIS_RT_TAG_LIMIT) * 2 + 1;
}

Value groupBase(OpBuilder &b, Location loc, Value word) {
  Value group = LLVM::LShrOp::create(b, loc, word, i64Constant(b, loc, 1));
  return LLVM::MulOp::create(b, loc, group, i64Constant(b, loc, IDRIS_RT_TAG_LIMIT));
}

Value at(OpBuilder &b, Location loc, Value cell, unsigned offset) {
  return LLVM::GEPOp::create(b, loc, ptrType(b.getContext()), b.getI8Type(), cell,
                             ArrayRef<LLVM::GEPArg>{static_cast<int32_t>(offset)});
}

unsigned cellAlignment() { return IDRIS_RT_WORD_BYTES; }

unsigned alignAt(unsigned base, unsigned offset) {
  return static_cast<unsigned>(llvm::MinAlign(base, offset));
}

Value nullComponent(OpBuilder &b, Location loc, Type component) {
  if (isa<LLVM::LLVMPointerType>(component))
    return LLVM::ZeroOp::create(b, loc, component);
  return LLVM::ConstantOp::create(b, loc, component, 0);
}

SmallVector<Value> unboxedSum(OpBuilder &b, Location loc, const layout::SumLayout &layout,
                              Tag tag, ArrayRef<ValueRange> fields) {
  SmallVector<std::optional<Value>> given(layout.slots.size());
  for (auto [index, values] : llvm::enumerate(fields))
    for (auto [slot, value] :
         llvm::zip_equal(layout.slotsOf(tag, static_cast<unsigned>(index)), values))
      given[slot] = value;
  SmallVector<Value> out;
  if (layout.tag)
    out.push_back(LLVM::ConstantOp::create(b, loc, *layout.tag, static_cast<uint32_t>(tag)));
  for (auto [slot, value] : llvm::enumerate(given))
    out.push_back(value ? *value : LLVM::ZeroOp::create(b, loc, layout.slots[slot]).getResult());
  return out;
}

SmallVector<Value> unboxedField(const layout::SumLayout &layout, ValueRange sum, Tag tag,
                                unsigned index) {
  return llvm::map_to_vector(layout.slotsOf(tag, index),
                             [&](unsigned slot) { return sum[layout.offset() + slot]; });
}

} // namespace idr::conversion
