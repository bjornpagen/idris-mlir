// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The static data that holds no other datum, its content its own bytes: a
// crash's message, a string, a big outside the small range, a constant
// array, and `nothing`, each a global written once under the name of its
// content.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Fold.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Symbols.h"
#include "idr/Conversion/Arrays.h"
#include "idr/Conversion/StaticData.h"
#include "idr/Conversion/Words.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/DialectResourceBlobManager.h"
#include "llvm/Support/raw_ostream.h"

// The runtime's C ABI: a string's and a big's static form is its cells',
// and the runtime itself reads a literal's text and says which words are
// small.
#include "idris_rt.h"

using namespace mlir;

namespace idr::conversion {

Value StaticData::message(OpBuilder &b, Location loc, StringRef text) {
  Named named = intern(loc, "msg", digestOf(text));
  auto type = LLVM::LLVMArrayType::get(b.getI8Type(), text.size());
  LLVM::GlobalOp message =
      global(named.name, named.key, type, /*isConstant=*/true, IDRIS_RT_WORD_BYTES,
             [&](OpBuilder &init) -> Value {
               return LLVM::ConstantOp::create(init, at, type, init.getStringAttr(text));
             });
  return LLVM::AddressOfOp::create(b, loc, message);
}

FailureOr<ConstantArray> ConstantArray::of(memref::GlobalOp global) {
  std::optional<Attribute> initial = global.getInitialValue();
  auto elements = initial ? dyn_cast<ElementsAttr>(*initial) : ElementsAttr();
  if (!global.getConstant() || !elements || !holdsWords(global.getType())) {
    global.emitError() << "internal error: idr-lower: @" << global.getSymName()
                       << " is no constant array of words";
    return failure();
  }
  return ConstantArray(global.getType(), elements);
}

// A constant array is a cell like any other, its header in front of its
// data: count 0, the runtime's persistent mark, so nothing counts, frees or
// reads past the header; the info of an array of the element's bytes with
// no object slot; and the number of elements. Its data is at the cell's
// element 0, as every array's is, at a word's alignment, row-major: dense
// elements reshaped, a resource's blob as it is, any other form's elements
// written out. Its name is its value's and type's canonical digests, kept
// for each attribute, so a large constant is printed once.
Value StaticData::constantArray(OpBuilder &b, Location loc, const ConstantArray &array) {
  MemRefType type = array.type();
  ElementsAttr values = array.elements();
  std::string key;
  llvm::raw_string_ostream(key) << canonicalHash(Attribute(values)) << " : "
                                << canonicalHash(Type(type));
  Named named = intern(loc, "array", digestOf(key));
  Type element = type.getElementType();
  int64_t count = type.getNumElements();
  auto dataType = LLVM::LLVMArrayType::get(element, static_cast<unsigned>(count));
  layout::CellInfo info = layout::CellInfo::array(layouts.element(element).stride, 0);
  SmallVector<Type> members = headerTypes(b.getContext());
  members.append({b.getI64Type(), dataType});
  auto cellType = LLVM::LLVMStructType::getLiteral(b.getContext(), members);
  LLVM::GlobalOp cell =
      global(named.name, named.key, cellType, /*isConstant=*/true, IDRIS_RT_WORD_BYTES,
             [&](OpBuilder &init) -> Value {
               auto flatType = RankedTensorType::get({count}, element);
               Attribute flat;
               if (auto dense = dyn_cast<DenseElementsAttr>(values))
                 flat = dense.reshape(flatType);
               else if (auto resource = dyn_cast<DenseResourceElementsAttr>(values))
                 flat = DenseResourceElementsAttr::get(flatType, resource.getRawHandle());
               else
                 flat = DenseElementsAttr::get(flatType,
                                               llvm::to_vector(values.getValues<Attribute>()));
               SmallVector<Value> fields = header(init, at, info);
               fields.append({i64Constant(init, at, count),
                              LLVM::ConstantOp::create(init, at, dataType, flat)});
               return pack(init, at, cellType, fields);
             });
  return LLVM::AddressOfOp::create(b, loc, cell);
}

// A string: the header (count 0: static data), the byte length and the
// scalar count, which the runtime computes, then the bytes.
LLVM::GlobalOp StaticData::string(Location loc, StringRef bytes) {
  Named named = intern(loc, "str", digestOf(bytes));
  MLIRContext *ctx = at.getContext();
  Type i64 = IntegerType::get(ctx, 64);
  SmallVector<Type> members = headerTypes(ctx);
  members.append({i64, i64});
  if (!bytes.empty())
    members.push_back(LLVM::LLVMArrayType::get(IntegerType::get(ctx, 8), bytes.size()));
  auto type = LLVM::LLVMStructType::getLiteral(ctx, members);
  auto scalars = static_cast<int64_t>(idris_rt_utf8_count(bytes.data(), bytes.size()));
  // Whether the string is ASCII is its two counts' agreement, which the
  // runtime reads; the header says nothing of it.
  auto write = [&](OpBuilder &init) -> Value {
    SmallVector<Value> values = header(init, at, layout::CellInfo::string());
    values.append({i64Constant(init, at, static_cast<int64_t>(bytes.size())),
                   i64Constant(init, at, scalars)});
    if (!bytes.empty())
      values.push_back(
          LLVM::ConstantOp::create(init, at, members.back(), init.getStringAttr(bytes)));
    return pack(init, at, type, values);
  };
  return global(named.name, named.key, type, /*isConstant=*/true, IDRIS_RT_WORD_BYTES, write);
}

// A big: the runtime reads the decimal text (one semantics for what a
// big literal denotes); a small result is its tagged word, any other a
// static idris_rt_bignum, its limbs in the same global, named from the
// literal. The folders' scope holds what the runtime gives and releases it
// when this returns, counted as theirs are; the limbs are read before then.
Value StaticData::big(OpBuilder &b, Location loc, BigAttr value, Digest key) {
  fold::Scope scope(b.getContext());
  idris_rt_big word = scope.big(value);
  if (idris_rt_word_is_small(word))
    return i64Constant(b, loc, word);
  Named named = intern(loc, "big", key);
  const auto *number = reinterpret_cast<const idris_rt_bignum *>(word);
  int64_t size = number->size;
  auto count = static_cast<size_t>(size < 0 ? -size : size);
  SmallVector<int64_t> limbs;
  const auto *digitsOf = reinterpret_cast<const uint64_t *>(number + 1);
  for (size_t i = 0; i < count; ++i)
    limbs.push_back(static_cast<int64_t>(digitsOf[i]));
  auto i64 = b.getI64Type();
  auto limbsType = LLVM::LLVMArrayType::get(i64, count);
  SmallVector<Type> members = headerTypes(b.getContext());
  members.append({i64, limbsType});
  auto type = LLVM::LLVMStructType::getLiteral(b.getContext(), members);
  LLVM::GlobalOp digits = global(named.name, named.key, type, /*isConstant=*/true,
                                 IDRIS_RT_WORD_BYTES,
                                 [&](OpBuilder &init) -> Value {
    Value limbsValue = LLVM::ConstantOp::create(
        init, at, limbsType,
        DenseElementsAttr::get(
            RankedTensorType::get({static_cast<int64_t>(count)}, init.getI64Type()),
            ArrayRef<int64_t>(limbs)));
    SmallVector<Value> values = header(init, at, layout::CellInfo::bignum());
    values.append({i64Constant(init, at, size), limbsValue});
    return pack(init, at, type, values);
  });
  Value address = LLVM::AddressOfOp::create(b, loc, digits);
  return LLVM::PtrToIntOp::create(b, loc, b.getI64Type(), address);
}

// The null object of a cell pointer: one static cell, a box's header with
// no object slot and nothing after it, count 0, so counting it changes
// nothing, and a cell, so every fact of a cell pointer holds of it. Poison
// is never read, so no field of it is.
LLVM::GlobalOp StaticData::nothing(Location loc) {
  Named named = intern(loc, "nothing", digestOf("nothing"));
  auto type = LLVM::LLVMStructType::getLiteral(at.getContext(), headerTypes(at.getContext()));
  return global(named.name, named.key, type, /*isConstant=*/true, IDRIS_RT_WORD_BYTES,
                [&](OpBuilder &init) -> Value {
                  return pack(init, at, type, header(init, at, layout::CellInfo::box(Tag{0}, 0)));
                });
}

} // namespace idr::conversion
