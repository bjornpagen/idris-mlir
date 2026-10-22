// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The static data that holds no other datum, its content its own bytes: a
// string, a big outside the small range, a constant array, `nothing`, and a
// text a crash site names, each a global made once under the name of its
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

// The runtime's C ABI: the runtime itself reads a literal's text, says
// which words are small, and counts a string's scalar values; a bignum's
// limbs follow its record.
#include "idris_rt.h"

using namespace mlir;

namespace idr::conversion {

FailureOr<ConstantArray> ConstantArray::of(memref::GlobalOp global) {
  std::optional<Attribute> initial = global.getInitialValue();
  auto elements = initial ? dyn_cast<ElementsAttr>(*initial) : ElementsAttr();
  if (!global.getConstant() || !elements || !holdsWords(global.getType())) {
    global.emitError() << "internal error: idr-lower-statics: @" << global.getSymName()
                       << " is no constant array of words";
    return failure();
  }
  return ConstantArray(global.getType(), elements, StaticNames::array(global));
}

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
  global(array.name(), cellType, Mutability::Constant, headerBytes,
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
                 SmallVector<Value> fields = header(init, info);
                 fields.append({i64Constant(init, at, count),
                                LLVM::ConstantOp::create(init, at, dataType, flat)});
                 return pack(init, cellType, fields);
               });
}

// A string: the header (count 0), the byte length and the scalar count,
// which the runtime computes, then the bytes. Whether the string is ASCII
// is its two counts' agreement, which the runtime reads; the header says
// nothing of it.
void StaticData::string(StringRef bytes) {
  MLIRContext *ctx = at.getContext();
  Type i32 = IntegerType::get(ctx, 32), i64 = IntegerType::get(ctx, 64);
  SmallVector<Type> members{i32, i32, i64, i64};
  if (!bytes.empty())
    members.push_back(LLVM::LLVMArrayType::get(IntegerType::get(ctx, 8), bytes.size()));
  auto type = LLVM::LLVMStructType::getLiteral(ctx, members);
  auto scalars = static_cast<int64_t>(idris_rt_utf8_count(bytes.data(), bytes.size()));
  global(StaticNames::string(bytes), type, Mutability::Constant, headerBytes,
         [&](OpBuilder &init) -> Value {
           SmallVector<Value> values = header(init, layout::CellInfo::string());
           values.append({i64Constant(init, at, static_cast<int64_t>(bytes.size())),
                          i64Constant(init, at, scalars)});
           if (!bytes.empty())
             values.push_back(
                 LLVM::ConstantOp::create(init, at, members.back(), init.getStringAttr(bytes)));
           return pack(init, type, values);
         });
}

// A big: the runtime reads the decimal text (one semantics for what a big
// literal denotes, the fold's: big.from_str's); a small result is its
// tagged word and no datum, any other a static idris_rt_bignum, its limbs in
// the same global. The fold's scope holds what the runtime gives and
// releases it when this returns; the limbs are read before then.
void StaticData::big(BigAttr value) {
  fold::Scope scope(at.getContext());
  idris_rt_big word = *fold::bigOf(scope, value);
  if (idris_rt_word_is_small(word))
    return;
  MLIRContext *ctx = at.getContext();
  const auto *number = reinterpret_cast<const idris_rt_bignum *>(word);
  int64_t size = number->size;
  auto count = static_cast<size_t>(size < 0 ? -size : size);
  SmallVector<int64_t> limbs;
  const auto *digitsOf = reinterpret_cast<const uint64_t *>(number + 1);
  for (size_t i = 0; i < count; ++i)
    limbs.push_back(static_cast<int64_t>(digitsOf[i]));
  Type i32 = IntegerType::get(ctx, 32), i64 = IntegerType::get(ctx, 64);
  auto limbsType = LLVM::LLVMArrayType::get(i64, count);
  auto type = LLVM::LLVMStructType::getLiteral(ctx, {i32, i32, i64, limbsType});
  global(StaticNames::big(value), type, Mutability::Constant, headerBytes,
         [&](OpBuilder &init) -> Value {
           Value limbsValue = LLVM::ConstantOp::create(
               init, at, limbsType,
               DenseElementsAttr::get(
                   RankedTensorType::get({static_cast<int64_t>(count)}, init.getI64Type()),
                   ArrayRef<int64_t>(limbs)));
           SmallVector<Value> values = header(init, layout::CellInfo::bignum());
           values.append({i64Constant(init, at, size), limbsValue});
           return pack(init, type, values);
         });
}

Value bigConstant(OpBuilder &b, Location loc, BigAttr value) {
  fold::Scope scope(b.getContext());
  idris_rt_big word = *fold::bigOf(scope, value);
  if (idris_rt_word_is_small(word))
    return i64Constant(b, loc, word);
  Value address = staticAddress(b, loc, StaticNames::big(value));
  return LLVM::PtrToIntOp::create(b, loc, b.getI64Type(), address);
}

// The null object of a cell pointer: one static cell, a header with no
// object slot and nothing after it, count 0, so counting it changes
// nothing, and a cell, so every fact of a cell pointer holds of it. Poison
// is never read, so no field of it is.
void StaticData::nothing() {
  MLIRContext *ctx = at.getContext();
  Type i32 = IntegerType::get(ctx, 32);
  auto type = LLVM::LLVMStructType::getLiteral(ctx, {i32, i32});
  global(StaticNames::nothing(), type, Mutability::Constant, headerBytes,
         [&](OpBuilder &init) -> Value {
           return pack(init, type, header(init, layout::CellInfo::constructor(Tag{0}, 0)));
         });
}

// A text of a crash site, as the runtime reads one (idris_rt_text): its
// length, then its bytes, which the runtime only writes out.
void StaticData::text(StringRef bytes) {
  MLIRContext *ctx = at.getContext();
  SmallVector<Type> members{IntegerType::get(ctx, 32)};
  if (!bytes.empty())
    members.push_back(LLVM::LLVMArrayType::get(IntegerType::get(ctx, 8), bytes.size()));
  auto type = LLVM::LLVMStructType::getLiteral(ctx, members);
  global(StaticNames::text(bytes), type, Mutability::Constant, headerBytes,
         [&](OpBuilder &init) -> Value {
           SmallVector<Value> values{i32Constant(init, at, static_cast<int64_t>(bytes.size()))};
           if (!bytes.empty())
             values.push_back(
                 LLVM::ConstantOp::create(init, at, members.back(), init.getStringAttr(bytes)));
           return pack(init, type, values);
         });
}

void StaticData::homes(unsigned sites) {
  if (sites == 0 || symbols.lookup(StaticNames::homes()))
    return;
  MLIRContext *ctx = at.getContext();
  auto type = LLVM::LLVMArrayType::get(LLVM::LLVMPointerType::get(ctx), sites);
  OpBuilder b = OpBuilder::atBlockBegin(&program->getRegion(0).front());
  auto made = LLVM::GlobalOp::create(b, at, type, /*isConstant=*/false, LLVM::Linkage::Private,
                                     StaticNames::homes(), Attribute(), headerBytes,
                                     /*addrSpace=*/0, /*dsoLocal=*/true,
                                     LLVM::ThreadLocalMode::LocalExec);
  b.createBlock(&made.getInitializerRegion());
  LLVM::ReturnOp::create(b, at, LLVM::ZeroOp::create(b, at, type).getResult());
  symbols.insert(made);
}

} // namespace idr::conversion
