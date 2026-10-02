// Lowering of arrays: one cell (idris_rt_array) of a length and its
// elements, and beside the cell its length, the memref's dimension
// (Layouts::components). The runtime allocates and frees the cell; the
// elements are read and written here, with a bounds check before each,
// since an index is a value the program computed: the index against the
// length, two registers, so that a check the program's own test made
// redundant folds away.
//
// Two element layouts. An element of one uncounted machine word (an
// integer, a double, a character, a byte, the tag of an enumeration) is
// addressed as the element of a memref: the array's view is a memref
// descriptor over the cell (the cell as what was allocated, the first
// element as the aligned pointer, the length as the size, stride 1), and a
// read or a write is memref.load or memref.store on it, which
// convert-to-llvm addresses as it addresses every memref. Any other element
// (counted components, which take and give references as they move, or
// several slots laid out as a cell's fields are) is addressed here by its
// slots' offsets from the element's start, since a memref element has one
// type and no count.

#include "Lower/Patterns.h"

#include "mlir/Conversion/LLVMCommon/MemRefBuilder.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Dialect/SCF/IR/SCF.h"

#include <cstddef>

using namespace mlir;

namespace idr::lower {

namespace {

Type ptrType(MLIRContext *ctx) { return LLVM::LLVMPointerType::get(ctx); }

Value i64Constant(OpBuilder &b, Location loc, int64_t value) {
  return LLVM::ConstantOp::create(b, loc, b.getI64Type(), b.getI64IntegerAttr(value));
}

// The element layout of `op`'s array, or an `unsupported` error at the op.
template <typename OpT> FailureOr<Element> elementOf(OpT op, Layouts &layouts) {
  std::expected<Element, std::string> element = layouts.element(op.getArrayType().getElementType());
  if (!element)
    return op.emitError() << "unsupported (layout): an array of "
                          << op.getArrayType().getElementType() << " cannot be built: "
                          << element.error();
  return std::move(*element);
}

// The memref an array of `element` is viewed as, when its element is one
// uncounted machine word: that word's type, at the stride the memref gives
// it; or null.
MemRefType wordView(Type element, const Element &layout, Layouts &layouts) {
  if (layout.slots.size() != 1 || layouts.counted(element).front())
    return {};
  Type word = layout.slots.front().type;
  if (!isa<IntegerType, FloatType>(word) || layout.stride != layouts.sizeOf(word))
    return {};
  return MemRefType::get({ShapedType::kDynamic}, word);
}

// The first element of the cell, after the header and the length.
Value elementsOf(OpBuilder &b, Location loc, Value cell) {
  return LLVM::GEPOp::create(b, loc, ptrType(b.getContext()), b.getI8Type(), cell,
                             ArrayRef<LLVM::GEPArg>{static_cast<int32_t>(sizeof(idris_rt_array))},
                             LLVM::GEPNoWrapFlags::inbounds);
}

// The address of element `index` (an i64) of the array cell, an element of
// several slots: `index` strides on from the first.
Value elementAt(OpBuilder &b, Location loc, Value cell, Value index, const Element &element) {
  Value offset = LLVM::MulOp::create(b, loc, index, i64Constant(b, loc, element.stride));
  return LLVM::GEPOp::create(b, loc, ptrType(b.getContext()), b.getI8Type(),
                             elementsOf(b, loc, cell), ArrayRef<LLVM::GEPArg>{offset},
                             LLVM::GEPNoWrapFlags::inbounds);
}

// The view of an array of words: the descriptor convert-to-llvm reads for
// a memref of `view`'s type, built over the cell. Its allocated pointer is
// the cell, which only the runtime frees, through the count; its aligned
// pointer the first element; its offset 0, its size the length, its stride
// 1. The cast to the memref meets its inverse in convert-to-llvm.
Value viewOf(OpBuilder &b, Location loc, Runtime &runtime, MemRefType view, Value cell,
             Value length) {
  auto descriptor = MemRefDescriptor::poison(b, loc, runtime.llvmTypeConverter().convertType(view));
  descriptor.setAllocatedPtr(b, loc, cell);
  descriptor.setAlignedPtr(b, loc, elementsOf(b, loc, cell));
  descriptor.setConstantOffset(b, loc, 0);
  descriptor.setSize(b, loc, 0, length);
  descriptor.setConstantStride(b, loc, 0, 1);
  return UnrealizedConversionCastOp::create(b, loc, view, Value(descriptor)).getResult(0);
}

// The index as memref ops take it.
Value asIndex(OpBuilder &b, Location loc, Value index) {
  return arith::IndexCastOp::create(b, loc, b.getIndexType(), index);
}

// Ends the program unless `index` is below `length`; a negative index is a
// large unsigned one.
void checkBounds(OpBuilder &b, Location loc, Runtime &runtime, Value length, Value index,
                 StringRef cause) {
  Value outside = LLVM::ICmpOp::create(b, loc, LLVM::ICmpPredicate::uge, index, length);
  runtime.crashIf(b, loc, outside, cause);
}

// The runtime's cell, then every element written with the fill: a word
// stored through the view; the components of any other element with the
// fill moved in with its one reference, and each element after the first
// taking one more, so the fill is incremented once per element and dropped
// once. The array is the cell and its length.
struct LowerArrayNew : IdrPattern<ArrayNewOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(ArrayNewOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    FailureOr<Element> element = elementOf(op, layouts);
    if (failed(element))
      return failure();
    // A negative size is an empty array (idris_rt_array_new).
    Value zero = arith::ConstantOp::create(rewriter, loc, rewriter.getI64IntegerAttr(0));
    Value length = arith::MaxSIOp::create(rewriter, loc, adaptor.getSize().front(), zero);
    Value cell = runtime.call(rewriter, loc, "idris_rt_array_new", ptrType(getContext()),
                              ValueRange{length, LLVM::ConstantOp::create(
                                                     rewriter, loc, rewriter.getI32Type(),
                                                     rewriter.getI32IntegerAttr(static_cast<int32_t>(
                                                         element->info.word())))});
    ValueRange fill = adaptor.getFill();
    MemRefType view = wordView(op.getArrayType().getElementType(), *element, layouts);
    SmallVector<bool> counted = layouts.counted(op.getFill().getType());
    for (auto [i, component] : llvm::enumerate(fill))
      counted[i] = counted[i] && !Runtime::isStatic(component);
    Value elements = view ? viewOf(rewriter, loc, runtime, view, cell, length) : Value();
    Value lower = arith::ConstantOp::create(rewriter, loc, rewriter.getIndexAttr(0));
    Value upper = asIndex(rewriter, loc, length);
    Value step = arith::ConstantOp::create(rewriter, loc, rewriter.getIndexAttr(1));
    auto loop = scf::ForOp::create(rewriter, loc, lower, upper, step);
    {
      OpBuilder::InsertionGuard guard(rewriter);
      rewriter.setInsertionPointToStart(loop.getBody());
      if (view) {
        memref::StoreOp::create(rewriter, loc, fill.front(), elements, loop.getInductionVar());
      } else {
        Value at = arith::IndexCastOp::create(rewriter, loc, rewriter.getI64Type(),
                                              loop.getInductionVar());
        runtime.store(rewriter, loc, elementAt(rewriter, loc, cell, at, *element), element->slots,
                      fill);
        runtime.inc(rewriter, loc, fill, counted);
      }
    }
    if (!view)
      runtime.dec(rewriter, loc, fill, counted);
    rewriter.replaceOpWithMultiple(op, {SmallVector<Value>{cell, length}, SmallVector<Value>{}});
    return success();
  }
};

// A word read through the view; the components of any other element, each
// counted one taking a reference of its own: the array keeps its own.
struct LowerArrayGet : IdrPattern<ArrayGetOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(ArrayGetOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    FailureOr<Element> element = elementOf(op, layouts);
    if (failed(element))
      return failure();
    ValueRange array = adaptor.getArray();
    Value index = adaptor.getIndex().front();
    if (std::optional<StringRef> cause = op.getCrashCause())
      checkBounds(rewriter, loc, runtime, array[1], index, *cause);
    if (MemRefType view = wordView(op.getArrayType().getElementType(), *element, layouts)) {
      Value elements = viewOf(rewriter, loc, runtime, view, array[0], array[1]);
      Value word = memref::LoadOp::create(rewriter, loc, elements, asIndex(rewriter, loc, index));
      rewriter.replaceOpWithMultiple(op, {SmallVector<Value>{word}, SmallVector<Value>{}});
      return success();
    }
    SmallVector<Value> value = runtime.load(
        rewriter, loc, elementAt(rewriter, loc, array[0], index, *element), element->slots);
    runtime.inc(rewriter, loc, value, layouts.counted(op.getValue().getType()));
    rewriter.replaceOpWithMultiple(op, {value, SmallVector<Value>{}});
    return success();
  }
};

// A word written through the view; for any other element the old one
// loses the array's reference, and the new one moves in.
struct LowerArraySet : IdrPattern<ArraySetOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(ArraySetOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    FailureOr<Element> element = elementOf(op, layouts);
    if (failed(element))
      return failure();
    ValueRange array = adaptor.getArray();
    Value index = adaptor.getIndex().front();
    if (std::optional<StringRef> cause = op.getCrashCause())
      checkBounds(rewriter, loc, runtime, array[1], index, *cause);
    if (MemRefType view = wordView(op.getArrayType().getElementType(), *element, layouts)) {
      Value elements = viewOf(rewriter, loc, runtime, view, array[0], array[1]);
      memref::StoreOp::create(rewriter, loc, adaptor.getValue().front(), elements,
                              asIndex(rewriter, loc, index));
      rewriter.replaceOpWithMultiple(op, {SmallVector<Value>{}});
      return success();
    }
    Value at = elementAt(rewriter, loc, array[0], index, *element);
    SmallVector<bool> counted = layouts.counted(op.getValue().getType());
    SmallVector<Value> old = runtime.load(rewriter, loc, at, element->slots);
    runtime.dec(rewriter, loc, old, counted);
    runtime.store(rewriter, loc, at, element->slots, adaptor.getValue());
    rewriter.replaceOpWithMultiple(op, {SmallVector<Value>{}});
    return success();
  }
};

// The length of an array, `memref.dim %a, %c0`: its length component, as
// the index the op gives. An array has the one dimension 0.
struct LowerDim : OpConversionPattern<memref::DimOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(memref::DimOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    if (!isArray(op.getSource().getType()))
      return op.emitError() << "unsupported (array): the dimension of "
                            << op.getSource().getType() << ", which is not an array";
    if (op.getConstantIndex() != 0)
      return op.emitError() << "unsupported (array): an array has the one dimension 0";
    rewriter.replaceOpWithNewOp<arith::IndexCastOp>(op, op.getType(), adaptor.getSource()[1]);
    return success();
  }
};

} // namespace

void populateArrayPatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                           Layouts &layouts, Runtime &runtime) {
  patterns.add<LowerArrayNew, LowerArrayGet, LowerArraySet>(converter, patterns.getContext(),
                                                            layouts, runtime);
  patterns.add<LowerDim>(converter, patterns.getContext());
}

} // namespace idr::lower
