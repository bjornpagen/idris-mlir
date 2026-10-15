// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Closures and suspensions. idr.closure captures a function's leading
// parameters, and idr.apply runs one. idr.suspend builds a cell and does
// not run its function; idr.force reads that cell, and the first entry
// computes the value and leaves it there. After idr-defunctionalize the cell
// is a box of a memo sum, and a force reads its state. A suspension of a
// value that already exists, idr.delay, is evaluated where it is built:
// forcing it computes nothing, and the force is the value.

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

} // namespace

//===----------------------------------------------------------------------===//
// idr.delay
//===----------------------------------------------------------------------===//

// The cell holds the operand's value; a world is never held.
LogicalResult DelayOp::verify() {
  if (isWorld(getValue().getType()))
    return emitOpError("holds a world; a world passes only as an argument or result");
  Type value = cast<LazyType>(unrestricted(getResult().getType())).getValue();
  if (unrestricted(value) != unrestricted(getValue().getType()))
    return emitOpError("holds ") << getValue().getType() << " in " << getResult().getType();
  return success();
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

// The value a suspension holds; a memo sum's `forced` state holds it once
// the cell is a box, which its type says.
LogicalResult ForceOp::verify() {
  Type cell = unrestricted(getSuspension().getType());
  Type value;
  if (auto lazy = dyn_cast<LazyType>(cell)) {
    value = lazy.getValue();
  } else {
    DataType data = cast<BoxType>(cell).getData();
    if (!data.isMemo())
      return emitOpError("forces ") << cell << ", which is not a memo sum";
    value = data.getCtor(data.getForcedTag()).fields[0];
  }
  if (unrestricted(getResult().getType()) != unrestricted(value))
    return emitOpError("forces ") << getSuspension().getType() << " to " << getResult().getType();
  return success();
}

// A view of a cell that memoizes has no effects: an unused force is
// erased. Not speculatable, so it is not moved onto a path that did not
// force. The write that shares the value is the lowering of this op, not a
// second effect. A force that takes its cell over, its operand owned, frees
// it; a force of a sum with a `by_name` label may run that label's output,
// and stays in order with output, which the sum's type says.
void ForceOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  Type cell = getSuspension().getType();
  if (isOwned(cell))
    effects.emplace_back(MemoryEffects::Free::get(), &getSuspensionMutable(),
                         ReferenceResource::get());
  DataType data = dataTypeOf(cell);
  if (data && llvm::any_of(data.getCtors(), [](const Ctor &ctor) { return ctor.byName; }))
    effects.emplace_back(MemoryEffects::Write::get(), IOResource::get());
}

// The force of an evaluated suspension is the value it holds. A linear
// value is taken this way only by the suspension's one force, which would
// otherwise use it twice.
OpFoldResult ForceOp::fold(FoldAdaptor) {
  auto delay = getSuspension().getDefiningOp<DelayOp>();
  if (!delay)
    return {};
  Value value = delay.getValue();
  if (value.getType() != getType())
    return {};
  if (quantityOf(value.getType()) == Quantity::One && !delay.getResult().hasOneUse())
    return {};
  return value;
}

void ForceOp::getCanonicalizationPatterns(RewritePatternSet &results, MLIRContext *context) {
  results.add<ForceOfOneUse, ForceInOneCase>(context);
}
