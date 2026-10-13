// The conversion's patterns for the closures, suspensions, applies, forces,
// constants and declarations, and the generic one that retypes every other
// op. Each takes its operands as the conversion remapped them and moves a
// value into its slot through the converter, so a coercion is made once
// per use that needs it.

#include "idr/IR/IdrDialect.h"
#include "idr/Analysis/Labels.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Symbols.h"
#include "idr/Transforms/Defunctionalize.h"

#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/OperationSupport.h"
#include "mlir/Transforms/DialectConversion.h"

#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::defunctionalize {

namespace {

// A closure or a suspension of `label` is its label's constructor in its
// key's sum, its captures moved into the label's parameters and held as
// the constructor's fields.
LogicalResult construct(Operation *op, StringAttr label, ValueRange captures,
                        const SlotTypeConverter &converter, ConversionPatternRewriter &rewriter) {
  Slots &slots = converter.slots();
  Key key = slots.keyOf(op->getResult(0));
  Type sum = slots.sumOf(key);
  if (!sum)
    return failure();
  SmallVector<Value> moved;
  if (failed(converter.coerceOperands(rewriter, op, captures, moved)))
    return failure();
  SmallVector<Value> held;
  for (auto [value, type] : llvm::zip(moved, slots.captureTypes(label, key)))
    held.push_back(heldAs(rewriter, op->getLoc(), value, type));
  auto ref = SymbolRefAttr::get(getSumName(sum).getAttr(), {FlatSymbolRefAttr::get(label)});
  rewriter.replaceOpWithNewOp<ConOp>(op, sum, ref, held);
  return success();
}

struct ClosurePattern : SlotPattern<ClosureOp> {
  using SlotPattern::SlotPattern;
  LogicalResult matchAndRewrite(ClosureOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    return construct(op, op.getCalleeAttr().getAttr(), adaptor.getCaptures(), converter(),
                     rewriter);
  }
};

struct SuspendPattern : SlotPattern<SuspendOp> {
  using SlotPattern::SlotPattern;
  LogicalResult matchAndRewrite(SuspendOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    return construct(op, op.getCalleeAttr().getAttr(), adaptor.getCaptures(), converter(),
                     rewriter);
  }
};

// An evaluated suspension is a cell already forced: its memo sum's `forced`
// constructor, holding the value.
struct DelayPattern : SlotPattern<DelayOp> {
  using SlotPattern::SlotPattern;
  LogicalResult matchAndRewrite(DelayOp op, OpAdaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Value value = evaluatedValue(op);
    Key key = slots().keyOf(op.getResult());
    Type sum = slots().sumOf(key);
    if (!value || !sum)
      return failure();
    Value remapped = rewriter.getRemappedValue(value);
    if (!remapped)
      return failure();
    Value held = heldAs(rewriter, op.getLoc(), remapped, slots().forcedType(key));
    auto ref = SymbolRefAttr::get(getSumName(sum).getAttr(),
                                  {FlatSymbolRefAttr::get(op.getContext(), memoForced)});
    rewriter.replaceOpWithNewOp<ConOp>(op, sum, ref, ValueRange{held});
    return success();
  }
};

// An apply of a converted key is a match over its labels, each region
// calling its label with the captures, then the arguments. A callee no
// value ever is gives poison: that apply never runs.
struct ApplyPattern : SlotPattern<ApplyOp> {
  using SlotPattern::SlotPattern;
  LogicalResult matchAndRewrite(ApplyOp apply, OpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Slots &keys = slots();
    Location loc = apply.getLoc();
    Key callee = keys.keyOf(apply.getCallee());
    SmallVector<Type> types;
    for (Value own : apply.getResults())
      types.push_back(keys.typeOf(own));
    if (!keys.isConverted(callee)) {
      if (!keys.unreached(callee))
        return failure();
      SmallVector<Value> poison;
      for (Type type : types)
        poison.push_back(ub::PoisonOp::create(rewriter, loc, type));
      rewriter.replaceOp(apply, poison);
      return success();
    }
    Value closure = adaptor.getCallee();
    SmallVector<Attribute> cases;
    for (StringAttr label : callee.second.getAsRange<StringAttr>())
      cases.push_back(FlatSymbolRefAttr::get(label));
    auto match = MatchOp::create(rewriter, loc, types, closure, rewriter.getArrayAttr(cases),
                                 static_cast<unsigned>(cases.size()));
    for (auto [label, region] :
         llvm::zip(callee.second.getAsRange<StringAttr>(), match.getRegions()))
      if (failed(call(apply, adaptor, label, region, closure, rewriter)))
        return failure();
    rewriter.replaceOp(apply, match.getResults());
    return success();
  }

  // The region of `label`: its captures bound at the scrutinee's grade and
  // held as its parameters, each argument moved into its slot, and each
  // result out of the label's into the apply's.
  LogicalResult call(ApplyOp apply, OpAdaptor adaptor, StringAttr label, Region &region,
                     Value closure, ConversionPatternRewriter &rewriter) const {
    Slots &keys = slots();
    Location loc = apply.getLoc();
    Key callee = keys.keyOf(apply.getCallee());
    OpBuilder::InsertionGuard guard(rewriter);
    SmallVector<Type> params = keys.captureTypes(label, callee), bound;
    for (Type param : params)
      bound.push_back(fieldType(closure.getType(), param));
    Block *block = rewriter.createBlock(&region, region.end(), bound,
                                        SmallVector<Location>(bound.size(), loc));
    SmallVector<Value> operands;
    for (auto [capture, param] : llvm::zip(block->getArguments(), params))
      operands.push_back(heldAs(rewriter, loc, capture, param));
    for (auto [i, arg] : llvm::enumerate(apply.getArgs())) {
      Value value = adaptor.getArgs()[i];
      if (isKeyed(arg.getType())) {
        Key to = keys.argumentKey(label, static_cast<unsigned>(params.size() + i));
        value = converter().coerce(rewriter, loc, value, keys.keyOf(arg), to,
                                   keys.typeOf(arg.getType(), to));
        if (!value)
          return failure();
      }
      operands.push_back(value);
    }
    FuncOp fn = keys.labels().function(label);
    SmallVector<Type> returned;
    for (auto [j, type] : llvm::enumerate(fn.getResultTypes()))
      returned.push_back(keys.typeOf(type, keys.resultKey(label, static_cast<unsigned>(j))));
    auto made = CallOp::create(rewriter, loc, returned, FlatSymbolRefAttr::get(label), operands,
                               /*arg_attrs=*/nullptr, /*res_attrs=*/nullptr, /*effects=*/nullptr);
    SmallVector<Value> yields;
    for (auto [j, own] : llvm::enumerate(apply.getResults())) {
      Value value = made.getResult(static_cast<unsigned>(j));
      if (isKeyed(own.getType())) {
        value = converter().coerce(rewriter, loc, value,
                                   keys.resultKey(label, static_cast<unsigned>(j)),
                                   keys.keyOf(own), keys.typeOf(own));
        if (!value)
          return failure();
      }
      yields.push_back(value);
    }
    YieldOp::create(rewriter, loc, yields);
    return success();
  }
};

// A force keeps its op and takes the cell's memo sum; the switch on the
// cell's state is the lowering's.
struct ForcePattern : SlotPattern<ForceOp> {
  using SlotPattern::SlotPattern;
  LogicalResult matchAndRewrite(ForceOp force, OpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    rewriter.replaceOpWithNewOp<ForceOp>(force, slots().typeOf(force.getResult()),
                                         adaptor.getSuspension());
    return success();
  }
};

// A constant with its closures and suspensions of converted keys as
// constructors. Constants share their parts, so each part in a slot is
// converted once per run of the conversion.
struct ConstantPattern : SlotPattern<ConstantOp> {
  using SlotPattern::SlotPattern;
  LogicalResult matchAndRewrite(ConstantOp constant, OpAdaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Attribute value = convert(constant.getValue(), slots().keyOf(constant.getResult()));
    rewriter.replaceOpWithNewOp<ConstantOp>(constant, slots().typeOf(constant.getResult()), value);
    return success();
  }

  // Constant `attr` in a slot of `slot`.
  Attribute convert(Attribute attr, const Key &slot) const {
    Slots &keys = slots();
    if (!keys.labels().holdsClosure(attr))
      return attr;
    if (auto it = parts.find({attr, slot}); it != parts.end())
      return it->second;
    MLIRContext *ctx = attr.getContext();
    Attribute result;
    if (auto closure = dyn_cast<ClosureAttr>(attr)) {
      StringAttr label = closure.getCallee().getAttr();
      SmallVector<Attribute> captures;
      for (auto [i, capture] : llvm::enumerate(closure.getCaptures()))
        captures.push_back(convert(capture, keys.argumentKey(label, static_cast<unsigned>(i))));
      auto array = ArrayAttr::get(ctx, captures);
      if (Type sum = keys.sumOf(slot))
        result = ConAttr::get(
            ctx, SymbolRefAttr::get(getSumName(sum).getAttr(), {closure.getCallee()}), array);
      else
        result = ClosureAttr::get(ctx, closure.getCallee(), array);
    } else {
      auto con = cast<ConAttr>(attr);
      SymbolRefAttr ctor = con.getCtor();
      auto fieldsOf = [&](ArrayAttr cell, function_ref<unsigned(unsigned)> index) {
        SmallVector<Attribute> fields;
        for (auto [i, value] : llvm::enumerate(cell))
          fields.push_back(
              convert(value, keys.fieldKey(ctor, index(static_cast<unsigned>(i)))));
        return ArrayAttr::get(ctx, fields);
      };
      if (!con.isRun()) {
        result = ConAttr::get(ctx, ctor, fieldsOf(con.getFields(), [](unsigned i) { return i; }));
      } else {
        // A run is converted cell by cell, its tail in the last cell's spine.
        unsigned spine = con.getSpine();
        SmallVector<ArrayAttr> cells;
        for (ArrayAttr cell : con.getRunCells())
          cells.push_back(fieldsOf(cell, [&](unsigned i) { return cellField(i, spine); }));
        result = ConAttr::getRun(ctx, ctor, spine, cells,
                                 convert(con.getTail(), keys.fieldKey(ctor, spine)));
      }
    }
    parts[{attr, slot}] = result;
    return result;
  }

  mutable llvm::DenseMap<std::pair<Attribute, Key>, Attribute> parts;
};

// A constructor's field holds its slot's type.
struct CtorPattern : SlotPattern<CtorOp> {
  using SlotPattern::SlotPattern;
  LogicalResult matchAndRewrite(CtorOp ctor, OpAdaptor,
                                ConversionPatternRewriter &rewriter) const override {
    ArrayAttr types = rewriter.getTypeArrayAttr(slots().fieldTypes(ctor));
    rewriter.modifyOpInPlace(ctor, [&] { ctor.setFieldTypesAttr(types); });
    return success();
  }
};

// A function's signature is its slots': each argument's and result's type
// from the key decision, by the function's name, since a result's key is
// the function's and not its type's. The body's block arguments convert
// with it, the entry block's by the signature.
struct FuncSignaturePattern : SlotPattern<FuncOp> {
  using SlotPattern::SlotPattern;
  LogicalResult matchAndRewrite(FuncOp fn, OpAdaptor,
                                ConversionPatternRewriter &rewriter) const override {
    FunctionType type = slots().functionType(fn);
    if (!fn.isExternal()) {
      TypeConverter::SignatureConversion signature(type.getNumInputs());
      for (auto [i, input] : llvm::enumerate(type.getInputs()))
        signature.addInputs(static_cast<unsigned>(i), input);
      if (failed(rewriter.convertRegionTypes(&fn.getBody(), converter(), &signature)))
        return failure();
    }
    rewriter.modifyOpInPlace(fn, [&] { fn.setFunctionType(type); });
    return success();
  }
};

// Any other op is made again with its operands moved into their slots, its
// results and region arguments of their slots' types, and its regions
// moved into the new op: a yield, a con, a field, a match, a linear
// entry or use, a poison, an array op.
struct RetypePattern : ConversionPattern {
  RetypePattern(const SlotTypeConverter &converter, MLIRContext *ctx)
      : ConversionPattern(converter, MatchAnyOpTypeTag(), /*benefit=*/1, ctx) {}

  LogicalResult matchAndRewrite(Operation *op, ArrayRef<Value> operands,
                                ConversionPatternRewriter &rewriter) const override {
    if (isa<ModuleOp, FuncOp, DataOp, CtorOp, CallOp, ReturnOp, ClosureOp, SuspendOp, DelayOp,
            ApplyOp, ForceOp, ConstantOp>(op))
      return failure();
    const auto &converter = *getTypeConverter<SlotTypeConverter>();
    Slots &slots = converter.slots();
    SmallVector<Value> moved;
    if (failed(converter.coerceOperands(rewriter, op, operands, moved)))
      return failure();
    OperationState state(op->getLoc(), op->getName());
    state.addOperands(moved);
    for (Value result : op->getResults())
      state.addTypes(slots.typeOf(result));
    state.addAttributes(op->getDiscardableAttrDictionary().getValue());
    state.propertiesAttr = op->getPropertiesAsAttribute();
    state.addSuccessors(op->getSuccessors());
    for (unsigned i = 0, n = op->getNumRegions(); i < n; ++i)
      state.addRegion();
    Operation *made = rewriter.create(state);
    for (auto [from, into] : llvm::zip(op->getRegions(), made->getRegions())) {
      rewriter.inlineRegionBefore(from, into, into.end());
      if (failed(rewriter.convertRegionTypes(&into, converter)))
        return failure();
    }
    rewriter.replaceOp(op, made->getResults());
    return success();
  }
};

} // namespace

void populateDefunctionalizePatterns(RewritePatternSet &patterns,
                                     const SlotTypeConverter &converter) {
  patterns.add<ClosurePattern, SuspendPattern, DelayPattern, ApplyPattern, ForcePattern,
               ConstantPattern, CtorPattern, FuncSignaturePattern, RetypePattern>(
      converter, patterns.getContext());
}

} // namespace idr::defunctionalize
