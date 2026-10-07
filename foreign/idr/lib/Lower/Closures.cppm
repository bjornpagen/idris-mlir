// idr.lower:closures: phase 2 of idr-lower for closures: a closure is a
// cell with the address of its code and its captures. Only idr-eval lowers
// closures; the program's own lowering meets none, as idr-defunctionalize
// has made each a sum.

export module idr.lower:closures;

import idr.mlir;
import idr.dialect;
import idr.layout;

import :idrPattern;
import :runtime;

using namespace mlir;

namespace idr::lower {

namespace {

// A new cell with its code and the captures.
struct LowerClosure : IdrPattern<ClosureOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(ClosureOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    const layout::Label &label = layouts.label(layouts.labelId(
        op.getCalleeAttr(), static_cast<unsigned>(op.getCaptures().size())));
    const layout::Cell &cell = layouts.closure(label);
    Value closure = runtime.allocate(rewriter, loc, cell.size, cell.info);
    runtime.store(rewriter, loc, closure, cell.fields.front(), runtime.code(rewriter, loc, label));
    for (auto [slots, values] :
         llvm::zip_equal(ArrayRef(cell.fields).drop_front(), adaptor.getCaptures()))
      runtime.store(rewriter, loc, closure, slots, values);
    rewriter.replaceOp(op, closure);
    return success();
  }
};

// A call of the closure's code with the closure and the
// arguments.
struct LowerApply : IdrPattern<ApplyOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(ApplyOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    Value closure = adaptor.getCallee().front();
    auto fn = cast<FnType>(op.getCallee().getType());
    SmallVector<Type> inputs{closure.getType()}, results;
    for (Type input : fn.getInputs())
      llvm::append_range(inputs, layouts.components(input));
    for (Type result : fn.getResults())
      llvm::append_range(results, layouts.components(result));
    auto type = rewriter.getFunctionType(inputs, results);
    Value code = runtime.load(rewriter, loc, closure, {{closure.getType(), 8}}).front();
    Value function = UnrealizedConversionCastOp::create(rewriter, loc, type, code).getResult(0);
    SmallVector<Value> args{closure};
    for (ValueRange arg : adaptor.getArgs())
      llvm::append_range(args, arg);
    auto call = func::CallIndirectOp::create(rewriter, loc, function, args);
    SmallVector<ValueRange> out;
    ResultRange values = call.getResults();
    for (Type result : fn.getResults()) {
      size_t n = layouts.components(result).size();
      out.push_back(values.take_front(n));
      values = values.drop_front(n);
    }
    rewriter.replaceOpWithMultiple(op, out);
    return success();
  }
};

// A new cell, large enough for the value as well as the captures, pointing
// at the entry that computes the value.
struct LowerSuspend : IdrPattern<SuspendOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(SuspendOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    const layout::Label &label = layouts.label(layouts.labelId(
        op.getCalleeAttr(), static_cast<unsigned>(op.getCaptures().size())));
    const layout::Cell &cell = layouts.closure(label);
    Value suspension = runtime.allocate(rewriter, loc, cell.size, cell.info);
    runtime.store(rewriter, loc, suspension, cell.fields.front(),
                  runtime.code(rewriter, loc, label));
    for (auto [slots, values] :
         llvm::zip_equal(ArrayRef(cell.fields).drop_front(), adaptor.getCaptures()))
      runtime.store(rewriter, loc, suspension, slots, values);
    rewriter.replaceOp(op, suspension);
    return success();
  }
};

// A call of whatever the cell points at. The first entry stores the value
// and replaces that pointer; a later one returns the stored value.
struct LowerForce : IdrPattern<ForceOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(ForceOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    Value suspension = adaptor.getSuspension().front();
    SmallVector<Type> inputs{suspension.getType()}, results;
    llvm::append_range(results, layouts.components(op.getType()));
    auto type = rewriter.getFunctionType(inputs, results);
    Value code = runtime.load(rewriter, loc, suspension, {{suspension.getType(), 8}}).front();
    Value function = UnrealizedConversionCastOp::create(rewriter, loc, type, code).getResult(0);
    auto call = func::CallIndirectOp::create(rewriter, loc, function, ValueRange{suspension});
    rewriter.replaceOpWithMultiple(op, {call.getResults()});
    return success();
  }
};

} // namespace

// The patterns of closures. Only idr-eval's lowering meets a closure: it
// runs code before idr-defunctionalize has made every closure of the
// program a sum.
export void populateClosurePatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                                    layout::Layouts &layouts, Runtime &runtime) {
  patterns.add<LowerClosure, LowerApply>(converter, patterns.getContext(), layouts, runtime);
}

// Suspensions stay suspensions through defunctionalization: the program's
// lowering meets them, and so does idr-eval's.
export void populateLazyPatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                                 layout::Layouts &layouts, Runtime &runtime) {
  patterns.add<LowerSuspend, LowerForce>(converter, patterns.getContext(), layouts, runtime);
}

} // namespace idr::lower
