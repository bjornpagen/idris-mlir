// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A memref at runtime (Arrays.h): its components, at function boundaries
// and in cells, and the descriptor upstream's memref ops read inside a
// function, each made from the other where a use needs it; and the
// addresses of its elements, after the cell's header.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/Conversion/Arrays.h"
#include "idr/Conversion/Words.h"

#include "mlir/Conversion/LLVMCommon/MemRefBuilder.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/Utils/StaticValueUtils.h"
#include "mlir/Transforms/DialectConversion.h"

// The runtime's C ABI: an array's cell is its header and length, then the
// elements, aligned to a word.
#include "idris_rt.h"

using namespace mlir;

namespace idr::conversion {

namespace {

// Where a memref's layout puts its fields: an identity layout fixes the
// offset at 0 and computes the strides from the sizes; any other gives each
// as a number or as dynamic.
struct LayoutFields {
  bool identity = true;
  int64_t offset = 0;
  SmallVector<int64_t> strides;
};

LayoutFields layoutFields(MemRefType type) {
  LayoutFields fields;
  if (type.getLayout().isIdentity())
    return fields;
  fields.identity = false;
  // A buffer's layout is the identity or strided (Layouts' components hold
  // the same fields), which always has strides and an offset.
  (void)type.getStridesAndOffset(fields.strides, fields.offset);
  return fields;
}

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

Value countOf(OpBuilder &b, Location loc, ArrayRef<OpFoldResult> sizes) {
  Value count = arith::ConstantIntOp::create(b, loc, 1, 64);
  for (OpFoldResult size : sizes)
    count = b.createOrFold<arith::MulIOp>(loc, count, asWord(b, loc, size));
  return count;
}

Descriptor unpack(OpBuilder &b, Location loc, MemRefType type, ValueRange components) {
  LayoutFields fields = layoutFields(type);
  Descriptor d;
  auto next = components.begin();
  d.cell = *next++;
  d.offset = fields.identity || !ShapedType::isDynamic(fields.offset)
                 ? OpFoldResult(word(b, fields.offset))
                 : OpFoldResult(*next++);
  for (int64_t extent : type.getShape())
    d.sizes.push_back(ShapedType::isDynamic(extent) ? OpFoldResult(*next++)
                                                    : OpFoldResult(word(b, extent)));
  if (fields.identity) {
    d.strides = rowMajor(b, loc, d.sizes);
  } else {
    for (int64_t stride : fields.strides)
      d.strides.push_back(ShapedType::isDynamic(stride) ? OpFoldResult(*next++)
                                                        : OpFoldResult(word(b, stride)));
  }
  assert(next == components.end() && "a memref's components are its descriptor's free fields");
  return d;
}

SmallVector<Value> pack(OpBuilder &b, Location loc, MemRefType type, const Descriptor &d) {
  LayoutFields fields = layoutFields(type);
  SmallVector<Value> components{d.cell};
  if (!fields.identity && ShapedType::isDynamic(fields.offset))
    components.push_back(asWord(b, loc, d.offset));
  for (auto [extent, size] : llvm::zip_equal(type.getShape(), d.sizes))
    if (ShapedType::isDynamic(extent))
      components.push_back(asWord(b, loc, size));
  if (!fields.identity)
    for (auto [field, stride] : llvm::zip_equal(fields.strides, d.strides))
      if (ShapedType::isDynamic(field))
        components.push_back(asWord(b, loc, stride));
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
  LayoutFields fields = layoutFields(type);
  // Only the fields the components hold are read.
  auto field = [&](bool dynamic, int64_t fixed, auto read) -> OpFoldResult {
    return dynamic ? OpFoldResult(read()) : OpFoldResult(word(b, fixed));
  };
  Descriptor d{descriptor.allocatedPtr(b, loc),
               field(!fields.identity && ShapedType::isDynamic(fields.offset), 0,
                     [&] { return descriptor.offset(b, loc); }),
               {},
               {}};
  for (auto [k, extent] : llvm::enumerate(type.getShape()))
    d.sizes.push_back(field(ShapedType::isDynamic(extent), extent, [&] {
      return descriptor.size(b, loc, static_cast<unsigned>(k));
    }));
  if (!fields.identity)
    for (auto [k, stride] : llvm::enumerate(fields.strides))
      d.strides.push_back(field(ShapedType::isDynamic(stride), stride, [&] {
        return descriptor.stride(b, loc, static_cast<unsigned>(k));
      }));
  return pack(b, loc, type, d);
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

} // namespace

void addMemrefConversions(TypeConverter &components, LLVMTypeConverter &descriptors,
                          const Layouts &layouts) {
  MLIRContext *ctx = &descriptors.getContext();
  // An element of ours is its bytes to upstream's patterns, which read only
  // its size, as the stride between elements: its slots are ours to read.
  descriptors.addConversion([&layouts, ctx](Type type) -> std::optional<Type> {
    if (type.getDialect().getNamespace() != IdrDialect::getDialectNamespace())
      return std::nullopt;
    return LLVM::LLVMArrayType::get(IntegerType::get(ctx, 8), layouts.element(type).stride);
  });
  descriptors.addTypeAttributeConversion(
      [](BaseMemRefType, WorldSpaceAttr) -> TypeConverter::AttributeConversionResult {
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
  descriptors.addSourceMaterialization(
      [](OpBuilder &b, IndexType type, ValueRange inputs, Location loc) -> Value {
        if (inputs.size() != 1 || !isa<IntegerType>(inputs.front().getType()))
          return {};
        return arith::IndexCastOp::create(b, loc, type, inputs.front());
      });

  components.addSourceMaterialization(
      [&descriptors](OpBuilder &b, MemRefType type, ValueRange inputs, Location loc) -> Value {
        return toMemref(b, loc, descriptors, type, inputs);
      });
  components.addTargetMaterialization(
      [](OpBuilder &b, IndexType type, ValueRange inputs, Location loc) -> Value {
        if (inputs.size() != 1 || !isa<IntegerType>(inputs.front().getType()))
          return {};
        return arith::IndexCastOp::create(b, loc, type, inputs.front());
      });
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
  return LLVM::GEPOp::create(b, loc, ptrType(b.getContext()), b.getI8Type(), cell,
                             ArrayRef<LLVM::GEPArg>{static_cast<int32_t>(sizeof(idris_rt_array))},
                             LLVM::GEPNoWrapFlags::inbounds);
}

Value elementAddress(OpBuilder &b, Location loc, const Descriptor &d, ValueRange indices,
                     unsigned stride) {
  // The element's place among the allocation's: the offset, then each index
  // along its stride, all in elements.
  OpFoldResult place = d.offset;
  for (auto [index, along] : llvm::zip(indices, d.strides)) {
    Value step = getConstantIntValue(along) == 1
                     ? index
                     : arith::MulIOp::create(b, loc, index, asWord(b, loc, along)).getResult();
    if (getConstantIntValue(place) == 0)
      place = step;
    else
      place = arith::AddIOp::create(b, loc, asWord(b, loc, place), step).getResult();
  }
  Value first = elementsOf(b, loc, d.cell);
  if (getConstantIntValue(place) == 0)
    return first;
  Value bytes = asWord(b, loc, place);
  if (stride != 1)
    bytes = arith::MulIOp::create(b, loc, bytes, arith::ConstantIntOp::create(b, loc, stride, 64));
  return LLVM::GEPOp::create(b, loc, ptrType(b.getContext()), b.getI8Type(), first,
                             ArrayRef<LLVM::GEPArg>{bytes}, LLVM::GEPNoWrapFlags::inbounds);
}

} // namespace idr::conversion
