// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Memrefs: their descriptors (Arrays.h), the cells the runtime allocates
// for them, their constants, and the arrays a world orders; the ops on
// buffers are Memrefs.cpp's. An access tests nothing itself: its index is
// within the array, by its type or by the guard before it.
//
// An element is laid out as a cell's fields are, object slots first
// (Layouts::element), and addressed by its slots' offsets from the
// element's start, since a memref element has one type and no count. A
// word element is the one slot of its own type, so the arrays a world
// orders write every element the same way. The reads and writes of words in
// buffers are left to upstream, which lowers and vectorizes them: they and
// the linalg ops over words see the memref their components describe.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Layout.h"
#include "idr/Conversion/Arrays.h"
#include "idr/Conversion/IdrPattern.h"
#include "idr/Conversion/Patterns.h"
#include "idr/Conversion/Runtime.h"
#include "idr/Conversion/Words.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/Utils/StaticValueUtils.h"
#include "mlir/Transforms/DialectConversion.h"
#include "llvm/Support/MathExtras.h"

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

// A new cell of `count` elements of `element`, from the runtime: fresh
// memory, which no other pointer reaches. Said at the call (the runtime's
// definition replaces the declaration's attributes when it is linked in),
// so that a loop over two arrays keeps what it accumulates in a register
// across the reads of the other.
Value newCell(OpBuilder &b, Location loc, Runtime &runtime, Value count,
              const layout::Element &element) {
  Value cell = runtime.call(b, loc, "idris_rt_array_new", ptrType(b.getContext()),
                            ValueRange{count, i32Constant(b, loc, element.info.word())});
  cell.getDefiningOp<LLVM::CallOp>().setResAttrsAttr(b.getArrayAttr(b.getDictionaryAttr(
      b.getNamedAttr(LLVM::LLVMDialect::getNoAliasAttrName(), b.getUnitAttr()))));
  return cell;
}

// A buffer's cell: as many elements as the product of the extents, a
// product past 64 bits being UINT64_MAX, which the runtime finds too large
// for any cell. The buffer is the cell and each dynamic size.
struct LowerAlloc : IdrPattern<memref::AllocOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(memref::AllocOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    MemRefType type = op.getType();
    if (!type.getLayout().isIdentity())
      return op.emitError() << "internal error: idr-lower: an allocation of " << type
                            << ", whose layout is not a cell's";
    if (std::optional<uint64_t> alignment = op.getAlignment();
        alignment && *alignment > IDRIS_RT_WORD_BYTES)
      return op.emitError() << "internal error: idr-lower: an allocation aligned to "
                            << *alignment << " bytes, past a cell's element";
    FailureOr<layout::Element> element = elementOf(op, type.getElementType(), layouts);
    if (failed(element))
      return failure();
    // The product saturates at each step, so a later empty extent still
    // makes it 0.
    uint64_t known = 1;
    for (int64_t extent : type.getShape())
      if (!ShapedType::isDynamic(extent))
        known = llvm::SaturatingMultiply(known, static_cast<uint64_t>(extent));
    Value most = i64Constant(rewriter, loc, -1);
    Value count = i64Constant(rewriter, loc, static_cast<int64_t>(known));
    auto pair = LLVM::LLVMStructType::getLiteral(getContext(),
                                                 {rewriter.getI64Type(), rewriter.getI1Type()});
    SmallVector<Value> components{Value()};
    for (ValueRange size : adaptor.getDynamicSizes()) {
      Value extent = indexWord(rewriter, loc, size.front());
      components.push_back(extent);
      Value product = LLVM::UMulWithOverflowOp::create(rewriter, loc, pair, count, extent);
      count = arith::SelectOp::create(rewriter, loc,
                                      LLVM::ExtractValueOp::create(rewriter, loc, product, 1), most,
                                      LLVM::ExtractValueOp::create(rewriter, loc, product, 0));
    }
    components[0] = newCell(rewriter, loc, runtime, count, *element);
    rewriter.replaceOpWithMultiple(op, {components});
    return success();
  }
};

// A constant array: its static cell, the header in front of the data.
struct LowerGetGlobal : IdrPattern<memref::GetGlobalOp> {
  LowerGetGlobal(const TypeConverter &converter, MLIRContext *ctx, const Layouts &layouts,
                 Runtime &runtime, const DenseMap<StringAttr, memref::GlobalOp> &globals)
      : IdrPattern(converter, ctx, layouts, runtime), globals(globals) {}

  LogicalResult matchAndRewrite(memref::GetGlobalOp op, OneToNOpAdaptor,
                                ConversionPatternRewriter &rewriter) const override {
    memref::GlobalOp global = globals.lookup(op.getNameAttr().getAttr());
    if (!global || !global.getConstant() || !global.getInitialValue() ||
        !isa<DenseElementsAttr>(*global.getInitialValue()) ||
        !holdsWords(global.getType()))
      return op.emitError() << "internal error: idr-lower: @" << op.getName()
                            << " is no constant array of words";
    if (std::optional<uint64_t> alignment = global.getAlignment();
        alignment && *alignment > IDRIS_RT_WORD_BYTES)
      return op.emitError() << "internal error: idr-lower: @" << op.getName() << " is aligned to "
                            << *alignment << " bytes, past a cell's element";
    rewriter.replaceOpWithMultiple(
        op, {SmallVector<Value>{runtime.constantArray(rewriter, op.getLoc(), global)}});
    return success();
  }

  const DenseMap<StringAttr, memref::GlobalOp> &globals;
};

// A new array a world orders, of the given sizes (a negative size is an
// empty dimension; an array of rank 0 has one element), each element the
// fill: its components stored in each element, each counted one taking a
// reference per element, and the fill's own given up after.
struct LowerArrayNew : IdrPattern<ArrayNewOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(ArrayNewOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    FailureOr<layout::Element> element =
        elementOf(op, op.getArrayType().getElementType(), layouts);
    if (failed(element))
      return failure();
    Value zero = arith::ConstantIntOp::create(rewriter, loc, 0, 64);
    SmallVector<Value> sizes;
    for (ValueRange size : adaptor.getSizes())
      sizes.push_back(arith::MaxSIOp::create(rewriter, loc, size.front(), zero));
    Value count = countOf(rewriter, loc, getAsOpFoldResult(sizes));
    Value cell = newCell(rewriter, loc, runtime, count, *element);
    ValueRange fill = adaptor.getFill();
    SmallVector<bool> counted = layouts.counted(op.getFill().getType());
    for (auto [i, component] : llvm::enumerate(fill))
      counted[i] = counted[i] && !StaticData::isStatic(component);
    Value lower = arith::ConstantIndexOp::create(rewriter, loc, 0);
    Value upper = arith::IndexCastOp::create(rewriter, loc, rewriter.getIndexType(), count);
    Value step = arith::ConstantIndexOp::create(rewriter, loc, 1);
    auto loop = scf::ForOp::create(rewriter, loc, lower, upper, step);
    {
      OpBuilder::InsertionGuard guard(rewriter);
      rewriter.setInsertionPointToStart(loop.getBody());
      Value at = indexWord(rewriter, loc, loop.getInductionVar());
      Descriptor d{cell, word(rewriter, 0), {}, {}};
      d.sizes.push_back(OpFoldResult(count));
      d.strides.push_back(word(rewriter, 1));
      runtime.store(rewriter, loc, elementAddress(rewriter, loc, d, at, element->stride),
                    element->slots, fill);
      runtime.inc(rewriter, loc, fill, counted);
    }
    runtime.dec(rewriter, loc, fill, counted);
    SmallVector<Value> array{cell};
    llvm::append_range(array, sizes);
    rewriter.replaceOpWithMultiple(op, {array, SmallVector<Value>{}});
    return success();
  }
};

// An element of an array a world orders. A read takes a reference of each
// counted component, which the array keeps its own of; a read that moves the
// element out takes the array's instead, and leaves the element's counted
// slots empty for the write that follows it, whose release of the old
// element then releases nothing. A write releases the old element and moves
// the new one in.
template <typename OpT>
struct LowerArrayAccess : IdrPattern<OpT> {
  using IdrPattern<OpT>::IdrPattern;
  LogicalResult matchAndRewrite(OpT op, typename IdrPattern<OpT>::OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    constexpr bool reading = std::is_same_v<OpT, ArrayGetOp>;
    Location loc = op.getLoc();
    MemRefType type = op.getArrayType();
    FailureOr<layout::Element> element = elementOf(op, type.getElementType(), this->layouts);
    if (failed(element))
      return failure();
    Descriptor d = unpack(rewriter, loc, type, adaptor.getArray());
    SmallVector<Value> indices;
    for (ValueRange index : adaptor.getIndices())
      indices.push_back(index.front());
    Value at = elementAddress(rewriter, loc, d, indices, element->stride);
    SmallVector<bool> counted = this->layouts.counted(op.getValue().getType());
    if constexpr (reading) {
      SmallVector<Value> value = readElement(rewriter, loc, this->runtime, at, *element);
      if (op.getMoves()) {
        SmallVector<layout::Slot> held;
        SmallVector<Value> nothing;
        for (auto [slot, isCounted] : llvm::zip_equal(element->slots, counted))
          if (isCounted) {
            held.push_back(slot);
            nothing.push_back(nullComponent(rewriter, loc, slot.type));
          }
        this->runtime.store(rewriter, loc, at, held, nothing);
      } else {
        this->runtime.inc(rewriter, loc, value, counted);
      }
      rewriter.replaceOpWithMultiple(op, {value, SmallVector<Value>{}});
    } else {
      writeElement(rewriter, loc, this->runtime, this->layouts, at, *element,
                   op.getValue().getType(), adaptor.getValue());
      rewriter.replaceOpWithMultiple(op, {SmallVector<Value>{}});
    }
    return success();
  }
};

} // namespace

Value indexWord(OpBuilder &b, Location loc, Value index) {
  return arith::IndexCastOp::create(b, loc, b.getI64Type(), index);
}

Value asIndex(OpBuilder &b, Location loc, OpFoldResult field) {
  if (auto attr = dyn_cast<Attribute>(field))
    return arith::ConstantIndexOp::create(b, loc, cast<IntegerAttr>(attr).getInt());
  return arith::IndexCastOp::create(b, loc, b.getIndexType(), cast<Value>(field));
}

FailureOr<layout::Element> elementOf(Operation *op, Type element, const Layouts &layouts) {
  std::expected<layout::Element, std::string> laid = layouts.element(element);
  if (!laid)
    return refuse(op, Rule::Layout) << "an array of " << element << " cannot be built: "
                                    << laid.error();
  return std::move(*laid);
}

Value countOf(OpBuilder &b, Location loc, ArrayRef<OpFoldResult> sizes) {
  Value count = arith::ConstantIntOp::create(b, loc, 1, 64);
  for (OpFoldResult size : sizes)
    count = b.createOrFold<arith::MulIOp>(loc, count, asWord(b, loc, size));
  return count;
}

SmallVector<Value> readElement(OpBuilder &b, Location loc, Runtime &runtime, Value address,
                               const layout::Element &element) {
  return runtime.load(b, loc, address, element.slots);
}

void writeElement(OpBuilder &b, Location loc, Runtime &runtime, const Layouts &layouts,
                  Value address, const layout::Element &element, Type type, ValueRange value) {
  SmallVector<bool> counted = layouts.counted(type);
  if (llvm::is_contained(counted, true))
    runtime.dec(b, loc, readElement(b, loc, runtime, address, element), counted);
  runtime.store(b, loc, address, element.slots, value);
}

bool holdsWords(MemRefType type) { return isa<IntegerType, FloatType>(type.getElementType()); }

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

// The patterns of the cells memrefs live in, constant or allocated, and of
// the arrays a world orders.
void populateArrayPatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                           const Layouts &layouts, Runtime &runtime,
                           const DenseMap<StringAttr, memref::GlobalOp> &globals) {
  MLIRContext *ctx = patterns.getContext();
  patterns.add<LowerAlloc, LowerArrayNew, LowerArrayAccess<ArrayGetOp>,
               LowerArrayAccess<ArraySetOp>>(converter, ctx, layouts, runtime);
  patterns.add<LowerGetGlobal>(converter, ctx, layouts, runtime, globals);
}

} // namespace idr::conversion
