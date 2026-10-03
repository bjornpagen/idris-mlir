// idr.lower:arrays: the patterns of arrays. An array is one cell
// (idris_rt_array) of a length and its elements, and beside the cell its
// length, the memref's dimension (layout::Layouts::components). The
// runtime allocates and frees the cell; the elements are read and written
// here, with a bounds check before each, since an index is a value the
// program computed: the index against the length, two registers, so that a
// check the program's own test made redundant folds away.
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

export module idr.lower:arrays;

import idr.mlir;
import idr.dialect;
import idr.layout;

import :arrayView;
import :idrPattern;
import :runtime;
import :words;

using namespace mlir;

namespace idr::lower {

namespace {

// The element layout of `op`'s array, or an `unsupported` error at the op.
template <typename OpT> FailureOr<layout::Element> elementOf(OpT op, layout::Layouts &layouts) {
  std::expected<layout::Element, std::string> element = layouts.element(op.getArrayType().getElementType());
  if (!element)
    return op.emitError() << "unsupported (layout): an array of "
                          << op.getArrayType().getElementType() << " cannot be built: "
                          << element.error();
  return std::move(*element);
}

// The memref an array of `element` is viewed as, when its element is one
// uncounted machine word: that word's type, at the stride the memref gives
// it; or null.
MemRefType wordView(Type element, const layout::Element &layout, layout::Layouts &layouts) {
  if (layout.slots.size() != 1 || layouts.counted(element).front())
    return {};
  Type word = layout.slots.front().type;
  if (!isa<IntegerType, FloatType>(word) || layout.stride != layouts.sizeOf(word))
    return {};
  return MemRefType::get({ShapedType::kDynamic}, word);
}

// The address of element `index` (an i64) of the array cell, an element of
// several slots: `index` strides on from the first.
Value elementAt(OpBuilder &b, Location loc, Value cell, Value index, const layout::Element &element) {
  Value offset = LLVM::MulOp::create(b, loc, index, i64Constant(b, loc, element.stride));
  return LLVM::GEPOp::create(b, loc, ptrType(b.getContext()), b.getI8Type(),
                             elementsOf(b, loc, cell), ArrayRef<LLVM::GEPArg>{offset},
                             LLVM::GEPNoWrapFlags::inbounds);
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
    FailureOr<layout::Element> element = elementOf(op, layouts);
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
    // A new cell is fresh memory, which no other pointer reaches: said at
    // the call (the runtime's definition replaces the declaration's
    // attributes when it is linked in), so that a loop over two arrays
    // keeps what it accumulates in a register across the reads of the other.
    cell.getDefiningOp<LLVM::CallOp>()->setAttr(
        "res_attrs", rewriter.getArrayAttr({rewriter.getDictionaryAttr(
                         {rewriter.getNamedAttr("llvm.noalias", rewriter.getUnitAttr())})}));
    ValueRange fill = adaptor.getFill();
    MemRefType view = wordView(op.getArrayType().getElementType(), *element, layouts);
    SmallVector<bool> counted = layouts.counted(op.getFill().getType());
    for (auto [i, component] : llvm::enumerate(fill))
      counted[i] = counted[i] && !Runtime::isStatic(component);
    Value elements = view ? arrayView(rewriter, loc, runtime, view, cell, length) : Value();
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
    FailureOr<layout::Element> element = elementOf(op, layouts);
    if (failed(element))
      return failure();
    ValueRange array = adaptor.getArray();
    Value index = adaptor.getIndex().front();
    if (std::optional<StringRef> cause = op.getCrashCause())
      checkBounds(rewriter, loc, runtime, array[1], index, *cause);
    if (MemRefType view = wordView(op.getArrayType().getElementType(), *element, layouts)) {
      Value elements = arrayView(rewriter, loc, runtime, view, array[0], array[1]);
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
    FailureOr<layout::Element> element = elementOf(op, layouts);
    if (failed(element))
      return failure();
    ValueRange array = adaptor.getArray();
    Value index = adaptor.getIndex().front();
    if (std::optional<StringRef> cause = op.getCrashCause())
      checkBounds(rewriter, loc, runtime, array[1], index, *cause);
    if (MemRefType view = wordView(op.getArrayType().getElementType(), *element, layouts)) {
      Value elements = arrayView(rewriter, loc, runtime, view, array[0], array[1]);
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
// the index the op gives. An array has the one dimension 0. Emit asks only
// that of an array, and no pass asks another, so any other dim is the
// compiler's error, never the program's.
struct LowerDim : OpConversionPattern<memref::DimOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(memref::DimOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    if (!isArray(op.getSource().getType()))
      return op.emitError() << "takes the dimension of " << op.getSource().getType()
                            << ", which is not an array";
    if (op.getConstantIndex() != 0)
      return op.emitError() << "takes a dimension of an array other than the constant 0, "
                               "and an array has the one dimension 0";
    rewriter.replaceOpWithNewOp<arith::IndexCastOp>(op, op.getType(), adaptor.getSource()[1]);
    return success();
  }
};

} // namespace

// The patterns of arrays.
export void populateArrayPatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                                  layout::Layouts &layouts, Runtime &runtime) {
  patterns.add<LowerArrayNew, LowerArrayGet, LowerArraySet>(converter, patterns.getContext(),
                                                            layouts, runtime);
  patterns.add<LowerDim>(converter, patterns.getContext());
}

} // namespace idr::lower
