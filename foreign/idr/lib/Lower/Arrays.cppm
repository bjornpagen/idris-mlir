// idr.lower:arrays: the patterns of arrays. An array is one cell
// (idris_rt_array) of a length and its elements, and beside the cell its
// size in each dimension, the memref's (layout::Layouts::components): an
// array of rank 1 its length, an IORef, of rank 0, nothing, its cell
// holding one element. The runtime allocates and frees the cell; the
// elements are read and written here, at an index the access's guard found
// below the length, or a proof did where it removed the guard: the access
// tests nothing itself.
//
// Two element layouts. An element of one uncounted machine word (an
// integer, a double, a character, a byte, the tag of an enumeration) is
// addressed as the element of a memref: the array's view is a memref
// descriptor over the cell (the cell as what was allocated, the first
// element as the aligned pointer, the sizes, stride 1), and a read or a
// write is memref.load or memref.store on it, which convert-to-llvm
// addresses as it addresses every memref. Any other element (counted
// components, which take and give references as they move, or several
// slots laid out as a cell's fields are) is addressed here by its slots'
// offsets from the element's start, since a memref element has one type
// and no count.

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

// The memref `array` is viewed as, when its element is one uncounted
// machine word: of the array's shape, over that word's type, at the stride
// the memref gives it; or null.
MemRefType wordView(MemRefType array, const layout::Element &layout, layout::Layouts &layouts) {
  if (layout.slots.size() != 1 || layouts.counted(array.getElementType()).front())
    return {};
  Type word = layout.slots.front().type;
  if (!isa<IntegerType, FloatType>(word) || layout.stride != layouts.sizeOf(word))
    return {};
  return MemRefType::get(array.getShape(), word);
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

// The runtime's cell, then every element written with the fill: a word
// stored through the view; the components of any other element with the
// fill moved in with its one reference, and each element after the first
// taking one more, so the fill is incremented once per element and dropped
// once. The array is the cell and its sizes; the cell holds as many
// elements as their product, one in an array of rank 0.
struct LowerArrayNew : IdrPattern<ArrayNewOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(ArrayNewOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    FailureOr<layout::Element> element = elementOf(op, layouts);
    if (failed(element))
      return failure();
    // A negative size is an empty dimension (idris_rt_array_new). The
    // product starts at 1, which a multiplication by it folds away.
    Value zero = arith::ConstantOp::create(rewriter, loc, rewriter.getI64IntegerAttr(0));
    Value length = arith::ConstantOp::create(rewriter, loc, rewriter.getI64IntegerAttr(1));
    SmallVector<Value> array{Value()};
    for (ValueRange size : adaptor.getSizes()) {
      Value clamped = arith::MaxSIOp::create(rewriter, loc, size.front(), zero);
      array.push_back(clamped);
      length = rewriter.createOrFold<arith::MulIOp>(loc, clamped, length);
    }
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
    array.front() = cell;
    ValueRange fill = adaptor.getFill();
    MemRefType view = wordView(op.getArrayType(), *element, layouts);
    SmallVector<bool> counted = layouts.counted(op.getFill().getType());
    for (auto [i, component] : llvm::enumerate(fill))
      counted[i] = counted[i] && !Runtime::isStatic(component);
    Value elements = view ? arrayView(rewriter, loc, runtime, view, array) : Value();
    Value lower = arith::ConstantOp::create(rewriter, loc, rewriter.getIndexAttr(0));
    Value upper = asIndex(rewriter, loc, length);
    Value step = arith::ConstantOp::create(rewriter, loc, rewriter.getIndexAttr(1));
    auto loop = scf::ForOp::create(rewriter, loc, lower, upper, step);
    {
      OpBuilder::InsertionGuard guard(rewriter);
      rewriter.setInsertionPointToStart(loop.getBody());
      if (view) {
        // The element at the loop's index, or the one element of an array
        // of rank 0, which the loop's one run writes.
        SmallVector<Value> at;
        if (view.getRank() != 0)
          at.push_back(loop.getInductionVar());
        memref::StoreOp::create(rewriter, loc, fill.front(), elements, at);
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
    rewriter.replaceOpWithMultiple(op, {array, SmallVector<Value>{}});
    return success();
  }
};

// A word through the view; any other element by its slots. A read takes a
// reference of each counted component, which the array keeps its own of;
// a read that moves the element out takes the array's instead, and leaves
// the element's counted slots null for the write that follows it, whose
// release of the old element then releases nothing. A write drops the old
// element's reference and moves the new one in.
template <typename OpT>
struct LowerArrayAccess : IdrPattern<OpT> {
  using IdrPattern<OpT>::IdrPattern;
  LogicalResult matchAndRewrite(OpT op, typename IdrPattern<OpT>::OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    constexpr bool reading = std::is_same_v<OpT, ArrayGetOp>;
    Location loc = op.getLoc();
    FailureOr<layout::Element> element = elementOf(op, this->layouts);
    if (failed(element))
      return failure();
    ValueRange array = adaptor.getArray();
    SmallVector<Value> indices;
    for (ValueRange index : adaptor.getIndices())
      indices.push_back(index.front());
    if (MemRefType view = wordView(op.getArrayType(), *element, this->layouts)) {
      Value elements = arrayView(rewriter, loc, this->runtime, view, array);
      SmallVector<Value> at;
      for (Value index : indices)
        at.push_back(asIndex(rewriter, loc, index));
      if constexpr (reading) {
        Value word = memref::LoadOp::create(rewriter, loc, elements, at);
        rewriter.replaceOpWithMultiple(op, {SmallVector<Value>{word}, SmallVector<Value>{}});
      } else {
        memref::StoreOp::create(rewriter, loc, adaptor.getValue().front(), elements, at);
        rewriter.replaceOpWithMultiple(op, {SmallVector<Value>{}});
      }
      return success();
    }
    // The element's place among the array's: its one index, or the first
    // and only element of an array of rank 0.
    Value index = indices.empty() ? i64Constant(rewriter, loc, 0) : indices.front();
    if constexpr (reading) {
      Value at = elementAt(rewriter, loc, array[0], index, *element);
      SmallVector<Value> value = this->runtime.load(rewriter, loc, at, element->slots);
      SmallVector<bool> counted = this->layouts.counted(op.getValue().getType());
      if (op.getMoves()) {
        SmallVector<layout::Slot> held;
        SmallVector<Value> nothing;
        for (auto [slot, isCounted] : llvm::zip_equal(element->slots, counted))
          if (isCounted) {
            held.push_back(slot);
            nothing.push_back(this->runtime.null(rewriter, loc, slot.type));
          }
        this->runtime.store(rewriter, loc, at, held, nothing);
      } else {
        this->runtime.inc(rewriter, loc, value, counted);
      }
      rewriter.replaceOpWithMultiple(op, {value, SmallVector<Value>{}});
    } else {
      Value at = elementAt(rewriter, loc, array[0], index, *element);
      SmallVector<bool> counted = this->layouts.counted(op.getValue().getType());
      SmallVector<Value> old = this->runtime.load(rewriter, loc, at, element->slots);
      this->runtime.dec(rewriter, loc, old, counted);
      this->runtime.store(rewriter, loc, at, element->slots, adaptor.getValue());
      rewriter.replaceOpWithMultiple(op, {SmallVector<Value>{}});
    }
    return success();
  }
};

// The length of an array, `memref.dim %a, %c0`: its length component, as
// the index the op gives. An array of rank 1 has the one dimension 0, and
// one of rank 0 none. Emit asks only that of an array of rank 1, and no
// pass asks another, so any other dim is the compiler's error, never the
// program's.
struct LowerDim : OpConversionPattern<memref::DimOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(memref::DimOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    if (!isRank1Array(op.getSource().getType()))
      return op.emitError() << "takes the dimension of " << op.getSource().getType()
                            << ", which is not an array of one dimension";
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
  patterns.add<LowerArrayNew, LowerArrayAccess<ArrayGetOp>, LowerArrayAccess<ArraySetOp>>(
      converter, patterns.getContext(), layouts, runtime);
  patterns.add<LowerDim>(converter, patterns.getContext());
}

} // namespace idr::lower
