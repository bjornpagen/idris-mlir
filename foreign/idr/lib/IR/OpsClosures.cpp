// Closures and suspensions. idr.closure captures a function's leading
// parameters, and idr.apply runs one. idr.suspend builds a cell and does
// not run its function; idr.force reads that cell, and the first entry
// computes the value and leaves it there. After idr-defunctionalize the cell
// is a box of a memo sum, and a force reads its state. A suspension of a
// value that already exists is evaluated where it is built: forcing it
// computes nothing, and the force is the value.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Canon.h"
#include "idr/IR/Symbols.h"

#include "mlir/IR/Matchers.h"
#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/DenseSet.h"

using namespace mlir;
using namespace idr;

namespace {

// A call of `callee` in place of a force or an apply. Neither carried
// effects, so the call carries none either: the next idr-effects writes
// them.
CallOp callOf(OpBuilder &builder, Location loc, FlatSymbolRefAttr callee, TypeRange results,
              ValueRange args) {
  return CallOp::create(builder, loc, results, callee, args, /*arg_attrs=*/nullptr,
                        /*res_attrs=*/nullptr, /*effects=*/nullptr);
}

// A suspension nothing else uses is this call. The body runs once, where
// it is forced. A shared suspension stays a cell: the first force stores
// the value and every later force reads it.
struct ForceOfOneUse : OpRewritePattern<ForceOp> {
  using OpRewritePattern::OpRewritePattern;

  LogicalResult matchAndRewrite(ForceOp force, PatternRewriter &rewriter) const override {
    auto suspend = force.getSuspension().getDefiningOp<SuspendOp>();
    if (!suspend || !suspend.getResult().hasOneUse())
      return failure();
    rewriter.setInsertionPoint(force);
    CallOp call = callOf(rewriter, force.getLoc(), suspend.getCalleeAttr(),
                         TypeRange(force.getResult().getType()), suspend.getCaptures());
    rewriter.replaceOp(force, call.getResults());
    rewriter.eraseOp(suspend);
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
      CallOp call = callOf(rewriter, force.getLoc(), suspend.getCalleeAttr(),
                           TypeRange(force.getResult().getType()), suspend.getCaptures());
      rewriter.replaceOp(force, call.getResults());
    }
    rewriter.eraseOp(suspend);
    return success();
  }
};

// A suspension whose body only builds a cell from values that exist
// already, constants and constructors of values from above, is built where
// the suspension is: forcing it would compute nothing, and the cell is
// then a value the delay yields from above. A constructor of a linear value
// stays, since the linear value is the delay's to use once. A cell
// idr-stack keeps in a frame is not moved out of the body it was kept for.
// One application leaves the delay evaluated, which this pattern no longer
// matches.
struct EvaluateDelay : OpRewritePattern<DelayOp> {
  using OpRewritePattern::OpRewritePattern;

  LogicalResult matchAndRewrite(DelayOp delay, PatternRewriter &rewriter) const override {
    Block &body = delay.getBody().front();
    if (body.empty() || !isa<YieldOp>(body.back()) || &body.front() == &body.back())
      return failure();
    auto *dialect = static_cast<IdrDialect *>(delay->getDialect());
    SmallVector<Operation *> moved;
    for (Operation &op : body.without_terminator()) {
      auto con = dyn_cast<ConOp>(op);
      bool constant = op.hasTrait<OpTrait::ConstantLike>() && op.getNumRegions() == 0;
      if (!constant && (!con || dialect->getStackAttrHelper().isAttrPresent(con)))
        return failure();
      // The block takes no argument and every op before the yield moves, so
      // an operand is defined above the delay or by an op moved before it.
      if (llvm::any_of(op.getOperandTypes(), isLinear))
        return failure();
      moved.push_back(&op);
    }
    for (Operation *op : moved)
      rewriter.moveOpBefore(op, delay);
    return success();
  }
};

} // namespace

mlir::Value idr::evaluatedValue(DelayOp delay) {
  if (delay.getBody().empty() || delay.getBody().front().empty())
    return {};
  auto yield = dyn_cast<YieldOp>(delay.getBody().front().front());
  if (!yield || yield.getNumOperands() != 1)
    return {};
  return yield.getOperand(0);
}

void DelayOp::getCanonicalizationPatterns(RewritePatternSet &results, MLIRContext *context) {
  results.add<EvaluateDelay>(context);
}

//===----------------------------------------------------------------------===//
// idr.closure
//===----------------------------------------------------------------------===//

// Worlds pass only as arguments and results, never
// in a closure.
LogicalResult ClosureOp::verify() {
  if (llvm::any_of(getCaptures().getTypes(), isWorld))
    return emitOpError("captures a world; a world passes only as an argument or result");
  // A closure holding a linear value is used once as well: applied where
  // it is made, or entered into a linear type (holdsLinear).
  if (holdsLinear(getResult()) && !takenOnce(getResult()))
    return emitOpError("captures a linear value, so its one use must apply it or enter it "
                       "into a linear type");
  return success();
}

// The callee's leading parameters are the captures, and the rest of its
// signature is the closure's type.
LogicalResult ClosureOp::verifySymbolUses(SymbolTableCollection &symbols) {
  auto fn = symbols.lookupNearestSymbolFrom<FuncOp>(*this, getCalleeAttr());
  if (!fn)
    return emitOpError("refers to an unknown function ") << getCalleeAttr();
  ArrayRef<Type> inputs = fn.getArgumentTypes();
  size_t captures = getCaptures().size();
  if (captures > inputs.size() ||
      !llvm::equal(getCaptures().getTypes(), inputs.take_front(captures)))
    return emitOpError("captures ")
           << getCaptures().getTypes() << ", which are not the leading parameters of "
           << getCalleeAttr();
  auto expected = FnType::get(getContext(), inputs.drop_front(captures), fn.getResultTypes());
  if (expected != getType())
    return emitOpError("has type ") << getType() << ", but a closure of " << getCalleeAttr()
                                    << " with these captures is " << expected;
  return success();
}

// A capture folds only as a constant the dialect builds at its type: a
// poison capture is the program's value where control never arrives, which
// no constant holds, so the closure stays an op around it.
OpFoldResult ClosureOp::fold(FoldAdaptor adaptor) {
  for (auto [capture, operand] : llvm::zip_equal(adaptor.getCaptures(), getCaptures()))
    if (!capture || !canon::buildable(capture, operand.getType()))
      return {};
  return ClosureAttr::get(getContext(), getCalleeAttr(),
                          ArrayAttr::get(getContext(), adaptor.getCaptures()));
}

//===----------------------------------------------------------------------===//
// idr.suspend
//===----------------------------------------------------------------------===//

LogicalResult SuspendOp::verify() {
  if (llvm::any_of(getCaptures().getTypes(), isWorld))
    return emitOpError("captures a world; a world passes only as an argument or result");
  // A suspension holding a linear value is used once as well: forced
  // where it is made, or entered into a linear type (holdsLinear).
  if (holdsLinear(getResult()) && !takenOnce(getResult()))
    return emitOpError("captures a linear value, so its one use must force it or enter it "
                       "into a linear type");
  return success();
}

// Every parameter is a capture, and the function's one result is the
// suspension's value. A world never is a capture.
LogicalResult SuspendOp::verifySymbolUses(SymbolTableCollection &symbols) {
  auto fn = symbols.lookupNearestSymbolFrom<FuncOp>(*this, getCalleeAttr());
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
  if (fn.getResultTypes().size() != 1 || unrestricted(fn.getResultTypes()[0]) != unrestricted(value))
    return emitOpError("suspends ") << getCalleeAttr() << ", which returns "
                                    << fn.getResultTypes() << ", where " << value << " is expected";
  return success();
}

// A capture folds only as a constant the dialect builds at its type: a
// poison capture is the program's value where control never arrives, which
// no constant holds, so the suspension stays an op around it.
OpFoldResult SuspendOp::fold(FoldAdaptor adaptor) {
  for (auto [capture, operand] : llvm::zip_equal(adaptor.getCaptures(), getCaptures()))
    if (!capture || !canon::buildable(capture, operand.getType()))
      return {};
  return ClosureAttr::get(getContext(), getCalleeAttr(),
                          ArrayAttr::get(getContext(), adaptor.getCaptures()));
}

//===----------------------------------------------------------------------===//
// idr.force
//===----------------------------------------------------------------------===//

// The value a suspension holds. A memo sum's `forced` state holds it once
// the cell is a box, which only its declaration says (verifySymbolUses).
LogicalResult ForceOp::verify() {
  auto lazy = dyn_cast<LazyType>(unrestricted(getSuspension().getType()));
  if (lazy && unrestricted(getResult().getType()) != unrestricted(lazy.getValue()))
    return emitOpError("forces ") << getSuspension().getType() << " to " << getResult().getType();
  return success();
}

LogicalResult ForceOp::verifySymbolUses(SymbolTableCollection &symbols) {
  Type cell = unrestricted(getSuspension().getType());
  if (isa<LazyType>(cell))
    return success();
  DataOp data = lookupData(symbols, *this, cell);
  if (!data || !isMemo(data))
    return emitOpError("forces ") << cell << ", which is not a memo sum";
  CtorOp forced = lookupCtor(data, memoForced);
  if (!forced || forced.getFieldTypes().size() != 1)
    return emitOpError("forces ") << cell << ", whose forced state holds no value";
  if (unrestricted(getResult().getType()) != unrestricted(forced.getFieldType(0)))
    return emitOpError("forces ") << getSuspension().getType() << " to " << getResult().getType();
  return success();
}

// A view of a cell that memoizes has no effects: an unused force is
// erased. Not speculatable, so it is not moved onto a path that did not
// force. The write that shares the value is the lowering of this op, not a
// second effect. A force that takes its cell over, its operand owned, frees
// it; a force of a sum with a `by_name` label may run that label's output,
// and stays in order with output. Only a box, which exists after
// idr-defunctionalize, has a declaration to read, with no table in hand: one
// scan of the module's top level.
void ForceOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  Type cell = getSuspension().getType();
  if (isOwned(cell))
    effects.emplace_back(MemoryEffects::Free::get(), &getSuspensionMutable(),
                         ReferenceResource::get());
  if (!getSumName(cell))
    return;
  DataOp data = declarationOf(*this, cell);
  if (data && llvm::any_of(data.getBody().front().getOps<CtorOp>(),
                           [](CtorOp ctor) { return ctor.getByName(); }))
    effects.emplace_back(MemoryEffects::Write::get(), IOResource::get());
}

// The force of an evaluated suspension is the value it holds. A linear
// value is taken this way only by the suspension's one force, which would
// otherwise use it twice.
OpFoldResult ForceOp::fold(FoldAdaptor) {
  auto delay = getSuspension().getDefiningOp<DelayOp>();
  if (!delay)
    return {};
  Value value = evaluatedValue(delay);
  if (!value || value.getType() != getType())
    return {};
  if (quantityOf(value.getType()) == Quantity::One && !delay.getResult().hasOneUse())
    return {};
  return value;
}

void ForceOp::getCanonicalizationPatterns(RewritePatternSet &results, MLIRContext *context) {
  results.add<ForceOfOneUse, ForceInOneCase>(context);
}

//===----------------------------------------------------------------------===//
// idr.apply
//===----------------------------------------------------------------------===//

// `idr.apply` of `idr.closure @f(caps)` or of a constant `#idr.closure<@f,
// [caps]>` is `idr.call @f(caps..., args...)`, as upstream's
// CallIndirectOp::canonicalize turns an indirect call of a constant into a
// direct call; `inline` does the rest. A closure made here moves its
// captures into the call; one that captures a linear value has this apply
// as its one use, as the verifier requires. A constant's captures are
// built at the callee's parameter types, which only its signature says:
// the one function this hook reads with no table in hand, a scan of the
// module's top level, while no pass writes a signature.
LogicalResult ApplyOp::canonicalize(ApplyOp apply, PatternRewriter &rewriter) {
  Value closureValue = canon::closureOf(apply);
  FlatSymbolRefAttr callee;
  SmallVector<Value> operands;
  if (auto closure = closureValue.getDefiningOp<ClosureOp>()) {
    callee = closure.getCalleeAttr();
    llvm::append_range(operands, closure.getCaptures());
  } else if (ClosureAttr constant; matchPattern(closureValue, m_Constant(&constant))) {
    callee = constant.getCallee();
    auto fn = SymbolTable::lookupNearestSymbolFrom<FuncOp>(apply, callee.getAttr());
    if (!fn || constant.getCaptures().size() > fn.getArgumentTypes().size())
      return failure();
    auto captures = llvm::zip(constant.getCaptures(), fn.getArgumentTypes());
    if (!llvm::all_of(captures, [](auto capture) {
          auto [value, type] = capture;
          return canon::buildable(value, type);
        }))
      return failure();
    for (auto [value, type] : captures)
      operands.push_back(canon::materialize(rewriter, apply.getLoc(), value, type));
  } else {
    return failure();
  }
  llvm::append_range(operands, apply.getArgs());
  rewriter.setInsertionPoint(apply);
  CallOp call = callOf(rewriter, apply.getLoc(), callee, apply.getResultTypes(), operands);
  rewriter.replaceOp(apply, call.getResults());
  return success();
}
