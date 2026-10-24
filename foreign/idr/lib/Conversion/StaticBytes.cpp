// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The static data that holds no other datum, its content its own bytes: a
// string, a big outside the small range, a constant array, `nothing`, a
// text a crash site or an account names, and the homes' cursors, each a
// global made once, when it is first met.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/Conversion/Arrays.h"
#include "idr/Conversion/StaticData.h"
#include "idr/Conversion/Words.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/DialectResourceBlobManager.h"

// The runtime's C ABI: the runtime itself says how a small big is held in
// its word and counts a string's scalar values; a bignum's limbs follow its
// record.
#include "idris_rt.h"

using namespace mlir;

namespace idr::conversion {

FailureOr<ConstantArray> ConstantArray::of(memref::GlobalOp global) {
  std::optional<Attribute> initial = global.getInitialValue();
  auto elements = initial ? dyn_cast<ElementsAttr>(*initial) : ElementsAttr();
  if (!global.getConstant() || !elements || !holdsWords(global.getType())) {
    global.emitError() << "internal error: idr-lower: @" << global.getSymName()
                       << " is no constant array of words";
    return failure();
  }
  return ConstantArray(global.getType(), elements, global.getSymNameAttr());
}

// The small range is the runtime's, IDRIS_RT_SMALL_MIN to IDRIS_RT_SMALL_MAX,
// and a value past a word is past it.
std::optional<int64_t> smallWordOf(const APInt &value) {
  if (value.getSignificantBits() > 64)
    return std::nullopt;
  int64_t number = value.getSExtValue();
  if (number < IDRIS_RT_SMALL_MIN || number > IDRIS_RT_SMALL_MAX)
    return std::nullopt;
  return idris_rt_small_word(number);
}

APInt naturalValue(uint64_t value) { return APInt(65, value); }

// A constant array is a cell like any other, its header in front of its
// data: count 0, so nothing counts, frees or reads past the header; the
// info of an array of the element's bytes with no object slot; and the
// number of elements. Its data is at the cell's element 0, as every
// array's is, at a word's alignment, row-major: dense elements reshaped, a
// resource's blob as it is, any other form's elements written out.
void StaticData::constantArray(const ConstantArray &array) {
  MLIRContext *ctx = at.getContext();
  MemRefType type = array.type();
  ElementsAttr values = array.elements();
  Type element = type.getElementType();
  int64_t count = type.getNumElements();
  Type i32 = IntegerType::get(ctx, 32), i64 = IntegerType::get(ctx, 64);
  auto dataType = LLVM::LLVMArrayType::get(element, static_cast<unsigned>(count));
  layout::CellInfo info = layout::CellInfo::array(layouts.element(element).stride, 0);
  auto cellType = LLVM::LLVMStructType::getLiteral(ctx, {i32, i32, i64, dataType});
  FlatSymbolRefAttr symbol = name("array");
  global(symbol, cellType, Mutability::Constant, headerBytes, [&](OpBuilder &init) -> Value {
    auto flatType = RankedTensorType::get({count}, element);
    Attribute flat;
    if (auto dense = dyn_cast<DenseElementsAttr>(values))
      flat = dense.reshape(flatType);
    else if (auto resource = dyn_cast<DenseResourceElementsAttr>(values))
      flat = DenseResourceElementsAttr::get(flatType, resource.getRawHandle());
    else
      flat = DenseElementsAttr::get(flatType, llvm::to_vector(values.getValues<Attribute>()));
    SmallVector<Value> fields = header(init, info);
    fields.append(
        {i64Constant(init, at, count), LLVM::ConstantOp::create(init, at, dataType, flat)});
    return pack(init, cellType, fields);
  });
  table.arrays.try_emplace(array.global(), symbol);
}

// A string: the header (count 0), the byte length and the scalar count,
// which the runtime computes, then the bytes. Whether the string is ASCII
// is its two counts' agreement, which the runtime reads; the header says
// nothing of it.
void StaticData::string(StringAttr value) {
  if (table.strings.contains(value))
    return;
  StringRef bytes = value.getValue();
  MLIRContext *ctx = at.getContext();
  Type i32 = IntegerType::get(ctx, 32), i64 = IntegerType::get(ctx, 64);
  SmallVector<Type> members{i32, i32, i64, i64};
  if (!bytes.empty())
    members.push_back(LLVM::LLVMArrayType::get(IntegerType::get(ctx, 8), bytes.size()));
  auto type = LLVM::LLVMStructType::getLiteral(ctx, members);
  auto scalars = static_cast<int64_t>(idris_rt_utf8_count(bytes.data(), bytes.size()));
  FlatSymbolRefAttr symbol = name("str");
  global(symbol, type, Mutability::Constant, headerBytes, [&](OpBuilder &init) -> Value {
    SmallVector<Value> values = header(init, layout::CellInfo::string());
    values.append({i64Constant(init, at, static_cast<int64_t>(bytes.size())),
                   i64Constant(init, at, scalars)});
    if (!bytes.empty())
      values.push_back(
          LLVM::ConstantOp::create(init, at, members.back(), init.getStringAttr(bytes)));
    return pack(init, type, values);
  });
  table.strings.try_emplace(value, symbol);
}

// A big in the small range is its word, no datum; any other a static
// idris_rt_bignum.
void StaticData::big(BigAttr value) {
  if (smallWordOf(value.getValue()) || table.bigs.contains(value))
    return;
  table.bigs.try_emplace(value, bignum(value.getValue()));
}

void StaticData::natural(uint64_t value) {
  APInt number = naturalValue(value);
  if (smallWordOf(number) || table.naturals.contains(value))
    return;
  table.naturals.try_emplace(value, bignum(number));
}

// A bignum as idris_rt_bignum holds one, in one global: the header, the
// count of limbs signed by the integer's sign (GMP's convention), then the
// limbs, the magnitude's 64-bit words, least significant first, none of
// them zero on top. Read off the integer's own words: one bit wider first,
// so that the magnitude of the least value of its width is a value of it.
FlatSymbolRefAttr StaticData::bignum(const APInt &value) {
  APInt wide = value.sext(value.getBitWidth() + 1);
  bool negative = wide.isNegative();
  APInt magnitude = negative ? -wide : wide;
  unsigned count = magnitude.getActiveWords();
  ArrayRef<uint64_t> words(magnitude.getRawData(), count);
  SmallVector<int64_t> limbs(llvm::map_range(
      words, [](uint64_t limb) { return static_cast<int64_t>(limb); }));
  int64_t size = negative ? -static_cast<int64_t>(count) : static_cast<int64_t>(count);
  MLIRContext *ctx = at.getContext();
  Type i32 = IntegerType::get(ctx, 32), i64 = IntegerType::get(ctx, 64);
  auto limbsType = LLVM::LLVMArrayType::get(i64, count);
  auto type = LLVM::LLVMStructType::getLiteral(ctx, {i32, i32, i64, limbsType});
  FlatSymbolRefAttr symbol = name("big");
  global(symbol, type, Mutability::Constant, headerBytes, [&](OpBuilder &init) -> Value {
    Value limbsValue = LLVM::ConstantOp::create(
        init, at, limbsType,
        DenseElementsAttr::get(RankedTensorType::get({static_cast<int64_t>(count)}, i64),
                               ArrayRef<int64_t>(limbs)));
    SmallVector<Value> values = header(init, layout::CellInfo::bignum());
    values.append({i64Constant(init, at, size), limbsValue});
    return pack(init, type, values);
  });
  return symbol;
}

// The null object of a cell pointer: one static cell, a header with no
// object slot and nothing after it, count 0, so counting it changes
// nothing, and a cell, so every fact of a cell pointer holds of it. Poison
// is never read, so no field of it is.
void StaticData::nothing() {
  MLIRContext *ctx = at.getContext();
  Type i32 = IntegerType::get(ctx, 32);
  auto type = LLVM::LLVMStructType::getLiteral(ctx, {i32, i32});
  table.nothingCell = name("nothing");
  global(table.nothingCell, type, Mutability::Constant, headerBytes,
         [&](OpBuilder &init) -> Value {
           return pack(init, type, header(init, layout::CellInfo::constructor(Tag{0}, 0)));
         });
}

// A text of a crash site or an account, as the runtime reads one
// (idris_rt_text): its length, then its bytes, which the runtime only
// writes out.
FlatSymbolRefAttr StaticData::text(StringRef bytes) {
  auto [entry, isNew] = texts.try_emplace(bytes);
  if (!isNew)
    return entry->second;
  MLIRContext *ctx = at.getContext();
  SmallVector<Type> members{IntegerType::get(ctx, 32)};
  if (!bytes.empty())
    members.push_back(LLVM::LLVMArrayType::get(IntegerType::get(ctx, 8), bytes.size()));
  auto type = LLVM::LLVMStructType::getLiteral(ctx, members);
  entry->second = name("text");
  global(entry->second, type, Mutability::Constant, headerBytes, [&](OpBuilder &init) -> Value {
    SmallVector<Value> values{i32Constant(init, at, static_cast<int64_t>(bytes.size()))};
    if (!bytes.empty())
      values.push_back(
          LLVM::ConstantOp::create(init, at, members.back(), init.getStringAttr(bytes)));
    return pack(init, type, values);
  });
  return entry->second;
}

void StaticData::site(SiteAttr site) {
  if (table.sites.contains(site))
    return;
  SiteTexts globals{text(site.getFunction()), text(site.getFile())};
  table.sites.try_emplace(site, globals);
}

void StaticData::account(StringAttr function) {
  table.accounts.try_emplace(function, text(function.getValue()));
}

void StaticData::homes(unsigned sites) {
  if (sites == 0)
    return;
  MLIRContext *ctx = at.getContext();
  auto type = LLVM::LLVMArrayType::get(LLVM::LLVMPointerType::get(ctx), sites);
  table.homeCursors = name("homes");
  OpBuilder b = OpBuilder::atBlockBegin(&program->getRegion(0).front());
  auto cursors = LLVM::GlobalOp::create(b, at, type, /*isConstant=*/false, LLVM::Linkage::Private,
                                        table.homeCursors.getValue(), Attribute(), headerBytes,
                                        /*addrSpace=*/0, /*dsoLocal=*/true,
                                        LLVM::ThreadLocalMode::LocalExec);
  b.createBlock(&cursors.getInitializerRegion());
  LLVM::ReturnOp::create(b, at, LLVM::ZeroOp::create(b, at, type).getResult());
}

} // namespace idr::conversion
