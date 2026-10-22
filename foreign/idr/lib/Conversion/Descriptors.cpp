// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A memref at runtime (Arrays.h): its components, at function boundaries
// and in cells, and the descriptor upstream's memref ops read inside a
// function, each made from the other where a use needs it, both walking
// the one plan of its descriptor's fields (layout::DescriptorFields).

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/Conversion/Arrays.h"
#include "idr/Conversion/Words.h"
#include "idr/Support/Match.h"

#include "mlir/Conversion/LLVMCommon/MemRefBuilder.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/Utils/StaticValueUtils.h"
#include "mlir/Transforms/DialectConversion.h"
#include "llvm/ADT/SmallVectorExtras.h"

#include <concepts>
#include <optional>

// The runtime's ABI, printed from the specification: the bytes of an
// array's cell before its elements, its header and its length, the same on
// every target, never the build machine's layout of the runtime's struct.
#include "idr/IR/Generated/RuntimeLayout.h.inc"

using namespace mlir;

namespace idr::conversion {

namespace {

Attribute word(OpBuilder &b, int64_t value) { return b.getI64IntegerAttr(value); }

// The row-major strides of `sizes`: the product of the sizes after each.
SmallVector<OpFoldResult> rowMajor(OpBuilder &b, Location loc, ArrayRef<OpFoldResult> sizes) {
  SmallVector<OpFoldResult> strides(sizes.size());
  OpFoldResult running = word(b, 1);
  for (size_t k = sizes.size(); k-- > 0;) {
    strides[k] = running;
    std::optional<int64_t> known = getConstantIntValue(running);
    std::optional<int64_t> size = getConstantIntValue(sizes[k]);
    if (known && size)
      running = word(b, *known * *size);
    else if (known == 1)
      running = sizes[k];
    else
      running = arith::MulIOp::create(b, loc, asWord(b, loc, running), asWord(b, loc, sizes[k]))
                    .getResult();
  }
  return strides;
}

} // namespace

bool holdsWords(MemRefType type) { return isa<IntegerType, FloatType>(type.getElementType()); }

bool leftToUpstream(MemRefType type) { return holdsWords(type) && !type.getMemorySpace(); }

Value indexWord(OpBuilder &b, Location loc, Value index) {
  return arith::IndexCastOp::create(b, loc, b.getI64Type(), index);
}

Value asIndex(OpBuilder &b, Location loc, OpFoldResult field) {
  if (auto attr = dyn_cast<Attribute>(field))
    return arith::ConstantIndexOp::create(b, loc, cast<IntegerAttr>(attr).getInt());
  return arith::IndexCastOp::create(b, loc, b.getIndexType(), cast<Value>(field));
}

SmallVector<Value> indicesOf(ArrayRef<ValueRange> indices) {
  return llvm::map_to_vector(indices, [](ValueRange index) { return index.front(); });
}

Value countOf(OpBuilder &b, Location loc, ArrayRef<OpFoldResult> sizes) {
  Value count = arith::ConstantIntOp::create(b, loc, 1, 64);
  for (OpFoldResult size : sizes)
    count = b.createOrFold<arith::MulIOp>(loc, count, asWord(b, loc, size));
  return count;
}

Descriptor unpack(OpBuilder &b, Location loc, MemRefType type, ValueRange components) {
  layout::DescriptorFields fields = layout::DescriptorFields::of(type);
  auto next = components.begin();
  auto read = [&](const layout::DescriptorField &field) {
    return match(
        field, [&](layout::Fixed fixed) { return OpFoldResult(word(b, fixed.value)); },
        [&](layout::Carried) { return OpFoldResult(*next++); });
  };
  Descriptor d;
  d.cell = *next++;
  d.offset = read(fields.offset);
  d.sizes = llvm::map_to_vector(fields.sizes, read);
  d.strides = fields.strides ? llvm::map_to_vector(*fields.strides, read)
                             : rowMajor(b, loc, d.sizes);
  return d;
}

SmallVector<Value> pack(OpBuilder &b, Location loc, MemRefType type, const Descriptor &d) {
  layout::DescriptorFields fields = layout::DescriptorFields::of(type);
  SmallVector<Value> components{d.cell};
  // A field the type fixes is no component; a carried one is the next.
  auto carry = [&](const layout::DescriptorField &field, OpFoldResult value) {
    match(
        field, [](layout::Fixed) {},
        [&](layout::Carried) { components.push_back(asWord(b, loc, value)); });
  };
  carry(fields.offset, d.offset);
  for (auto [field, size] : llvm::zip_equal(fields.sizes, d.sizes))
    carry(field, size);
  if (fields.strides)
    for (auto [field, stride] : llvm::zip_equal(*fields.strides, d.strides))
      carry(field, stride);
  return components;
}

Value descriptorOf(OpBuilder &b, Location loc, Type llvmType, MemRefType type,
                   ValueRange components) {
  Descriptor d = unpack(b, loc, type, components);
  MemRefDescriptor descriptor = MemRefDescriptor::poison(b, loc, llvmType);
  descriptor.setAllocatedPtr(b, loc, d.cell);
  descriptor.setAlignedPtr(b, loc, elementsOf(b, loc, d.cell));
  descriptor.setOffset(b, loc, asWord(b, loc, d.offset));
  for (auto [k, size, stride] : llvm::enumerate(d.sizes, d.strides)) {
    descriptor.setSize(b, loc, static_cast<unsigned>(k), asWord(b, loc, size));
    descriptor.setStride(b, loc, static_cast<unsigned>(k), asWord(b, loc, stride));
  }
  return descriptor;
}

SmallVector<Value> componentsOf(OpBuilder &b, Location loc, MemRefType type, Value value) {
  MemRefDescriptor descriptor(value);
  layout::DescriptorFields fields = layout::DescriptorFields::of(type);
  // Only the fields the components hold are read.
  SmallVector<Value> components{descriptor.allocatedPtr(b, loc)};
  auto carry = [&](const layout::DescriptorField &field, std::invocable auto read) {
    match(
        field, [](layout::Fixed) {}, [&](layout::Carried) { components.push_back(read()); });
  };
  carry(fields.offset, [&] { return descriptor.offset(b, loc); });
  for (auto [k, size] : llvm::enumerate(fields.sizes))
    carry(size, [&] { return descriptor.size(b, loc, static_cast<unsigned>(k)); });
  if (fields.strides)
    for (auto [k, stride] : llvm::enumerate(*fields.strides))
      carry(stride, [&] { return descriptor.stride(b, loc, static_cast<unsigned>(k)); });
  return components;
}

namespace {

// A memref a legal op holds: its descriptor, from the components or as an
// upstream op left it, cast to the memref.
Value toMemref(OpBuilder &b, Location loc, const LLVMTypeConverter &descriptors, MemRefType type,
               ValueRange values) {
  Type llvmType = descriptors.convertType(type);
  if (!llvmType)
    return {};
  Value descriptor = values.size() == 1 && values.front().getType() == llvmType
                         ? values.front()
                         : descriptorOf(b, loc, llvmType, type, values);
  return UnrealizedConversionCastOp::create(b, loc, type, descriptor).getResult(0);
}

// An index given as the word a conversion made of it, as the index it is.
Value wordAsIndex(OpBuilder &b, IndexType type, ValueRange inputs, Location loc) {
  if (inputs.size() != 1 || !isa<IntegerType>(inputs.front().getType()))
    return {};
  return arith::IndexCastOp::create(b, loc, type, inputs.front());
}

} // namespace

void addMemrefConversions(TypeConverter &components, LLVMTypeConverter &descriptors,
                          const Layouts &layouts) {
  MLIRContext *ctx = &descriptors.getContext();
  // An element of ours is its bytes to upstream's patterns, which read only
  // its size, as the stride between elements: its slots are ours to read.
  descriptors.addConversion([&layouts, ctx](Type type) -> std::optional<Type> {
    if (!isa<IdrDialect>(type.getDialect()))
      return std::nullopt;
    return LLVM::LLVMArrayType::get(IntegerType::get(ctx, 8), layouts.element(type).stride);
  });
  descriptors.addTypeAttributeConversion(
      [](BaseMemRefType, MutableAttr) -> TypeConverter::AttributeConversionResult {
        return TypeConverter::AttributeConversionResult::result(Attribute());
      });
  // Registered after upstream's own, so tried first: upstream would make a
  // descriptor of one pointer whose aligned pointer is the cell itself.
  descriptors.addTargetMaterialization([](OpBuilder &b, LLVM::LLVMStructType llvmType,
                                          ValueRange inputs, Location loc,
                                          Type original) -> Value {
    auto type = dyn_cast_or_null<MemRefType>(original);
    if (!type)
      return {};
    return descriptorOf(b, loc, llvmType, type, inputs);
  });
  descriptors.addSourceMaterialization(
      [&descriptors](OpBuilder &b, MemRefType type, ValueRange inputs, Location loc) -> Value {
        return toMemref(b, loc, descriptors, type, inputs);
      });
  // An extent upstream gives as the converted index, read by an op of ours
  // or a legal one as the index it is.
  descriptors.addSourceMaterialization(wordAsIndex);

  components.addSourceMaterialization(
      [&descriptors](OpBuilder &b, MemRefType type, ValueRange inputs, Location loc) -> Value {
        return toMemref(b, loc, descriptors, type, inputs);
      });
  components.addTargetMaterialization(wordAsIndex);
  components.addTargetMaterialization([](OpBuilder &b, TypeRange, ValueRange inputs, Location loc,
                                         Type original) -> SmallVector<Value> {
    auto type = dyn_cast_or_null<MemRefType>(original);
    if (!type || inputs.size() != 1 || !isa<LLVM::LLVMStructType>(inputs.front().getType()))
      return {};
    return componentsOf(b, loc, type, inputs.front());
  });
}

Value asWord(OpBuilder &b, Location loc, OpFoldResult field) {
  if (auto attr = dyn_cast<Attribute>(field))
    return arith::ConstantIntOp::create(b, loc, cast<IntegerAttr>(attr).getInt(), 64);
  return cast<Value>(field);
}

Value elementsOf(OpBuilder &b, Location loc, Value cell) {
  return LLVM::GEPOp::create(
      b, loc, ptrType(b.getContext()), b.getI8Type(), cell,
      ArrayRef<LLVM::GEPArg>{static_cast<int32_t>(idr::runtime::arrayHeaderBytes)},
      LLVM::GEPNoWrapFlags::inbounds);
}

} // namespace idr::conversion
