// Lowering of arrays: one cell (idris_rt_array) of a length and its
// elements, each laid out as a cell's fields are, and beside the cell its
// length, the memref's dimension (Layouts::components). The runtime
// allocates and frees the cell; the elements are read and written here,
// with a bounds check before each, since an index is a value the program
// computed: the index against the length, two registers, so that a check
// the program's own test made redundant folds away.

#include "Lower/Patterns.h"

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

// The address of element `index` (an i64) of the array cell: after the
// header and the length, `index` strides on.
Value elementAt(OpBuilder &b, Location loc, Value cell, Value index, const Element &element) {
  Value offset = LLVM::MulOp::create(b, loc, index, i64Constant(b, loc, element.stride));
  offset = LLVM::AddOp::create(b, loc, offset, i64Constant(b, loc, sizeof(idris_rt_array)));
  return LLVM::GEPOp::create(b, loc, ptrType(b.getContext()), b.getI8Type(), cell,
                             ArrayRef<LLVM::GEPArg>{offset}, LLVM::GEPNoWrapFlags::inbounds);
}

// Ends the program unless `index` is below `length`; a negative index is a
// large unsigned one.
void checkBounds(OpBuilder &b, Location loc, Runtime &runtime, Value length, Value index,
                 StringRef cause) {
  Value outside = LLVM::ICmpOp::create(b, loc, LLVM::ICmpPredicate::uge, index, length);
  runtime.crashIf(b, loc, outside, cause);
}

// The runtime's cell, then every element written with the fill's
// components: the fill moved in with its one reference, and each element
// after the first takes one more, so the fill is incremented once per
// element and dropped once. The array is the cell and its length.
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
    SmallVector<bool> counted = layouts.counted(op.getFill().getType());
    for (auto [i, component] : llvm::enumerate(fill))
      counted[i] = counted[i] && !Runtime::isStatic(component);
    Type index = rewriter.getIndexType();
    Value lower = arith::ConstantOp::create(rewriter, loc, rewriter.getIndexAttr(0));
    Value upper = arith::IndexCastOp::create(rewriter, loc, index, length);
    Value step = arith::ConstantOp::create(rewriter, loc, rewriter.getIndexAttr(1));
    auto loop = scf::ForOp::create(rewriter, loc, lower, upper, step);
    {
      OpBuilder::InsertionGuard guard(rewriter);
      rewriter.setInsertionPointToStart(loop.getBody());
      Value at = arith::IndexCastOp::create(rewriter, loc, rewriter.getI64Type(),
                                            loop.getInductionVar());
      runtime.store(rewriter, loc, elementAt(rewriter, loc, cell, at, *element), element->slots,
                    fill);
      runtime.inc(rewriter, loc, fill, counted);
    }
    runtime.dec(rewriter, loc, fill, counted);
    rewriter.replaceOpWithMultiple(op, {SmallVector<Value>{cell, length}, SmallVector<Value>{}});
    return success();
  }
};

// The element's components, each counted one taking a reference of its own:
// the array keeps its own.
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
    SmallVector<Value> value = runtime.load(
        rewriter, loc, elementAt(rewriter, loc, array[0], index, *element), element->slots);
    runtime.inc(rewriter, loc, value, layouts.counted(op.getValue().getType()));
    rewriter.replaceOpWithMultiple(op, {value, SmallVector<Value>{}});
    return success();
  }
};

// The old element loses the array's reference, and the new one moves in.
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
