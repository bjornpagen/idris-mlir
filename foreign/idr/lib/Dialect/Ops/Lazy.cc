// idr.suspend builds a cell and does not run its function. idr.force
// reads that cell: the first entry computes the value and leaves it there.

#include "idr/Idr.h"

#include "mlir/IR/Matchers.h"
#include "mlir/IR/PatternMatch.h"

using namespace mlir;
using namespace idr;

namespace {

// A suspension nothing else uses is this call. The body runs once, where
// it is forced. A shared suspension stays a cell: the first force stores
// the value and every later force reads it.
struct ForceOfOneUse : OpRewritePattern<ForceOp> {
  using OpRewritePattern::OpRewritePattern;

  LogicalResult matchAndRewrite(ForceOp force, PatternRewriter &rewriter) const override {
    auto suspend = force.getSuspension().getDefiningOp<SuspendOp>();
    if (!suspend || !suspend.getResult().hasOneUse())
      return failure();
    rewriter.replaceOpWithNewOp<func::CallOp>(force, suspend.getCalleeAttr(),
                                              TypeRange(force.getResult().getType()),
                                              suspend.getCaptures());
    rewriter.eraseOp(suspend);
    return success();
  }
};

// A constant suspension used once has nothing to share with. The call is
// the force, and inlining then sees the body. A second force keeps the
// cell, which is where a pure constant is computed once.
struct ForceOfOneConstant : OpRewritePattern<ForceOp> {
  using OpRewritePattern::OpRewritePattern;

  LogicalResult matchAndRewrite(ForceOp force, PatternRewriter &rewriter) const override {
    if (!force.getSuspension().hasOneUse())
      return failure();
    Attribute attr;
    if (!matchPattern(force.getSuspension(), m_Constant(&attr)))
      return failure();
    auto closure = dyn_cast<ClosureAttr>(attr);
    if (!closure)
      return failure();
    auto fn = SymbolTable::lookupNearestSymbolFrom<func::FuncOp>(force, closure.getCallee());
    if (!fn || closure.getCaptures().size() > fn.getNumArguments())
      return failure();
    Dialect *dialect = rewriter.getContext()->getLoadedDialect<IdrDialect>();
    SmallVector<Value> operands;
    operands.reserve(closure.getCaptures().size());
    for (auto [value, type] : llvm::zip(closure.getCaptures(), fn.getArgumentTypes())) {
      Operation *plain =
          dialect->materializeConstant(rewriter, value, unrestricted(type), force.getLoc());
      if (!plain)
        return failure();
      operands.push_back(plain->getResult(0));
    }
    rewriter.replaceOpWithNewOp<func::CallOp>(force, closure.getCallee(),
                                              TypeRange(force.getResult().getType()), operands);
    return success();
  }
};

// The forces sit in different cases of one match, so only one of them runs
// and the cell would never be read twice. Each case calls.
struct ForceInOneCase : OpRewritePattern<SuspendOp> {
  using OpRewritePattern::OpRewritePattern;

  LogicalResult matchAndRewrite(SuspendOp suspend, PatternRewriter &rewriter) const override {
    if (suspend.getResult().hasOneUse())
      return failure();
    Operation *match = nullptr;
    SmallVector<ForceOp> forces;
    for (OpOperand &use : suspend.getResult().getUses()) {
      auto force = dyn_cast<ForceOp>(use.getOwner());
      Operation *parent = force ? force->getParentOp() : nullptr;
      if (!force || !isa<MatchOp, MatchLitOp>(parent) || (match && match != parent))
        return failure();
      match = parent;
      forces.push_back(force);
    }
    if (!match || match->isAncestor(suspend) || forces.size() < 2)
      return failure();
    llvm::SmallDenseSet<Region *, 4> regions;
    for (ForceOp force : forces)
      if (!regions.insert(force->getParentRegion()).second)
        return failure();
    for (ForceOp force : forces) {
      rewriter.setInsertionPoint(force);
      auto call = func::CallOp::create(rewriter, force.getLoc(), suspend.getCalleeAttr(),
                                       TypeRange(force.getResult().getType()),
                                       suspend.getCaptures());
      rewriter.replaceOp(force, call.getResults());
    }
    rewriter.eraseOp(suspend);
    return success();
  }
};

// `\_ => force thunk`, with the thunk used only there. The call replaces
// the suspension inside the continuation, so the cell is never built and
// the call stays where the force was: a tail call of the continuation
// stays one.
struct ForceAtCapture : OpRewritePattern<ClosureOp> {
  using OpRewritePattern::OpRewritePattern;

  LogicalResult matchAndRewrite(ClosureOp closure, PatternRewriter &rewriter) const override {
    auto wrapper = SymbolTable::lookupNearestSymbolFrom<func::FuncOp>(closure, closure.getCalleeAttr());
    if (!wrapper || wrapper.isExternal() || !llvm::hasSingleElement(wrapper.getBody()))
      return failure();
    Block &body = wrapper.getBody().front();
    if (body.getOperations().size() != 2)
      return failure();
    auto force = dyn_cast<ForceOp>(body.front());
    auto ret = dyn_cast<func::ReturnOp>(body.back());
    auto arg = force ? dyn_cast<BlockArgument>(force.getSuspension()) : BlockArgument();
    if (!force || !ret || ret.getNumOperands() != 1 || ret.getOperand(0) != force.getResult() ||
        !arg || arg.getOwner() != &body || arg.getArgNumber() >= closure.getCaptures().size())
      return failure();
    unsigned index = arg.getArgNumber();
    auto suspend = closure.getCaptures()[index].getDefiningOp<SuspendOp>();
    if (!suspend || !suspend.getResult().hasOneUse())
      return failure();
    auto callee = SymbolTable::lookupNearestSymbolFrom<func::FuncOp>(suspend, suspend.getCalleeAttr());
    if (!callee)
      return failure();
    auto nCaps = static_cast<unsigned>(suspend.getCaptures().size());
    SmallVector<Type> inputs;
    inputs.reserve(wrapper.getNumArguments() - 1 + nCaps);
    for (unsigned i = 0, n = wrapper.getNumArguments(); i < n; ++i) {
      if (i == index) {
        llvm::append_range(inputs, suspend.getCaptures().getTypes());
        continue;
      }
      inputs.push_back(wrapper.getArgument(i).getType());
    }
    if (!llvm::hasSingleElement(callee.getBody()))
      return failure();
    auto type = FunctionType::get(rewriter.getContext(), inputs, wrapper.getResultTypes());
    // The body is the callee's, so the name says which one. A call would not
    // keep it: a function nothing calls is already dead to the inliner, which
    // erases it after this pipeline.
    std::string name =
        (wrapper.getSymName() + "$" + std::to_string(index) + "$" + callee.getSymName()).str();
    auto existing = SymbolTable::lookupNearestSymbolFrom<func::FuncOp>(
        wrapper, FlatSymbolRefAttr::get(rewriter.getContext(), name));
    if (existing && existing.getFunctionType() != type)
      return failure();
    if (!existing) {
      rewriter.setInsertionPoint(wrapper);
      existing = func::FuncOp::create(rewriter, wrapper.getLoc(), name, type);
      existing.setPrivate();
      if (auto effects = callee->getAttr("idr.effects"))
        existing->setAttr("idr.effects", effects);
      if (callee->hasAttr("idr.total"))
        existing->setAttr("idr.total", rewriter.getUnitAttr());
      Block *entry = rewriter.createBlock(&existing.getBody(), existing.getBody().end(), inputs,
                                          SmallVector<Location>(inputs.size(), wrapper.getLoc()));
      IRMapping mapping;
      for (unsigned i = 0; i < nCaps; ++i)
        mapping.map(callee.getArgument(i), entry->getArgument(index + i));
      rewriter.setInsertionPointToStart(entry);
      for (Operation &op : callee.getBody().front())
        rewriter.clone(op, mapping);
    }
    rewriter.setInsertionPoint(closure);
    SmallVector<Value> captures;
    captures.reserve(closure.getCaptures().size() - 1 + nCaps);
    for (auto [i, cap] : llvm::enumerate(closure.getCaptures())) {
      if (i == index) {
        llvm::append_range(captures, suspend.getCaptures());
        continue;
      }
      captures.push_back(cap);
    }
    auto neu = ClosureOp::create(rewriter, closure.getLoc(), closure.getType(),
                                 FlatSymbolRefAttr::get(rewriter.getContext(), name), captures);
    rewriter.replaceOp(closure, neu.getResult());
    rewriter.eraseOp(suspend);
    return success();
  }
};

} // namespace

LogicalResult SuspendOp::verify() {
  if (llvm::any_of(getCaptures().getTypes(), isWorld))
    return emitOpError("captures a world; a world passes only as an argument or result");
  // A suspension holding a linear value is used once as well: forced
  // where it is made, or entered into a linear type. Any other use could
  // force it twice and use the linear capture twice.
  if (llvm::none_of(getCaptures().getTypes(),
                    [](Type type) { return quantityOf(type) == Quantity::One; }))
    return success();
  if (getResult().use_empty())
    return success();
  OpOperand &use = *getResult().getUses().begin();
  auto force = dyn_cast<ForceOp>(use.getOwner());
  bool linear = getResult().hasOneUse() &&
                (isa<LinEnterOp>(use.getOwner()) || (force && force.getSuspension() == getResult()));
  if (!linear)
    return emitOpError("captures a linear value, so its one use must force it or enter it "
                       "into a linear type");
  return success();
}

// Every parameter is a capture, and the function's one result is the
// suspension's value. A world never is a capture.
LogicalResult SuspendOp::verifySymbolUses(SymbolTableCollection &symbols) {
  auto fn = symbols.lookupNearestSymbolFrom<func::FuncOp>(*this, getCalleeAttr());
  if (!fn)
    return emitOpError("refers to an unknown function ") << getCalleeAttr();
  ArrayRef<Type> inputs = fn.getArgumentTypes();
  if (getCaptures().size() != inputs.size() ||
      !llvm::equal(getCaptures().getTypes(), inputs))
    return emitOpError("captures ")
           << getCaptures().getTypes() << ", which are not the parameters of " << getCalleeAttr();
  // The function returns the carrier. After idr-rc that return is owned
  // and this cell is too; the carrier is what the two still share.
  Type value = cast<LazyType>(unrestricted(getResult().getType())).getValue();
  if (fn.getNumResults() != 1 || unrestricted(fn.getResultTypes()[0]) != unrestricted(value))
    return emitOpError("suspends ") << getCalleeAttr() << ", which returns "
                                    << fn.getResultTypes() << ", where " << value << " is expected";
  return success();
}

OpFoldResult SuspendOp::fold(FoldAdaptor adaptor) {
  if (llvm::is_contained(adaptor.getCaptures(), Attribute()))
    return {};
  return ClosureAttr::get(getContext(), getCalleeAttr(),
                          ArrayAttr::get(getContext(), adaptor.getCaptures()));
}

LogicalResult ForceOp::verify() {
  Type value = cast<LazyType>(unrestricted(getSuspension().getType())).getValue();
  if (unrestricted(getResult().getType()) != unrestricted(value))
    return emitOpError("forces ") << getSuspension().getType() << " to " << getResult().getType();
  return success();
}

// No effects: an unused force is erased. Not speculatable, so it is not
// moved onto a path that did not force. The write that shares the value
// is the lowering of this op, not a second effect.
void ForceOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &) {}

void ForceOp::getCanonicalizationPatterns(RewritePatternSet &results, MLIRContext *context) {
  results.add<ForceOfOneUse, ForceOfOneConstant, ForceInOneCase, ForceAtCapture>(context);
}
