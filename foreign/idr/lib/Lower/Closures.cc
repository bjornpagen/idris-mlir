// Phase 2 of idr-lower for closures: a closure is a cell with the address of
// its code and its captures. Only idr-eval lowers closures; the
// program's own lowering meets none, as idr-defunctionalize has made each
// a sum.

#include "Lower/Patterns.h"

using namespace mlir;

namespace idr::lower {

namespace {

// A new cell with its code and the captures.
struct LowerClosure : IdrPattern<ClosureOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(ClosureOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    const Label &label = layouts.label(layouts.labelId(
        op.getCalleeAttr(), static_cast<unsigned>(op.getCaptures().size())));
    const Cell &cell = layouts.closure(label);
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
} // namespace

void populateClosurePatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                             Layouts &layouts, Runtime &runtime) {
  patterns.add<LowerClosure, LowerApply>(converter, patterns.getContext(), layouts, runtime);
}

} // namespace idr::lower
