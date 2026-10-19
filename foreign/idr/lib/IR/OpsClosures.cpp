// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Closures and suspensions. idr.closure captures a function's leading
// parameters, and idr.apply runs one. idr.suspend builds a cell and does
// not run its function; idr.force reads that cell, and the first entry
// computes the value and leaves it there. After idr-defunctionalize the cell
// is a box of a memo sum, a force is a call of its dispatch, and the
// dispatch exchanges the cell's state through idr.memo.run, which moves the
// captures out and the value in. A suspension of a value that already
// exists, idr.delay, is evaluated where it is built: forcing it computes
// nothing, and the force is the value.

#include "idr/IR/Arrays.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Canon.h"
#include "idr/IR/Symbols.h"

#include "mlir/IR/Matchers.h"
#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/DenseSet.h"

using namespace mlir;
using namespace idr;

namespace {

// A call of `callee` in place of a force: what it may do is the callee's.
CallOp callOf(OpBuilder &builder, Location loc, FlatSymbolRefAttr callee, TypeRange results,
              ValueRange args) {
  return CallOp::create(builder, loc, results, callee, args, /*arg_attrs=*/nullptr,
                        /*res_attrs=*/nullptr);
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
      if (!force || !isa<MatchOpInterface>(parent) || (match && match != parent))
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
// idr.closure
//===----------------------------------------------------------------------===//

// The callee's leading parameters are the captures, and the rest of its
// signature is the closure's carrier, whatever quantity the captures give
// it (Idr_LinearWhenACaptureIs).
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
  if (expected != unrestricted(getType()))
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

// Every parameter is a capture, and the function's one result is the
// suspension's value.
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

//===----------------------------------------------------------------------===//
// idr.memo.run
//===----------------------------------------------------------------------===//

DataType MemoRunOp::getDataType() { return dataTypeOf(getCell().getType()); }

// The cell is in the state of a label that memoizes: a label run by name
// leaves its cell as it is. The region binds that label's captures, each
// at its field's type at any permission: plain before idr-rc, owned after
// it where it holds references, as the cell's own reference moves out with
// it.
LogicalResult MemoRunOp::verify() {
  FailureOr<std::reference_wrapper<const Ctor>> found =
      idr::detail::ctorAt(*this, getCell().getType(), getTag());
  if (failed(found))
    return failure();
  const Ctor &ctor = *found;
  const auto *label = std::get_if<role::Label>(&ctor.role);
  if (!label || label->byName)
    return emitOpError("runs @") << ctor.name.getValue()
                                 << ", which is no label of the cell that memoizes";
  Block &body = getRegion().front();
  if (body.getNumArguments() != ctor.fields.size())
    return emitOpError("binds ") << body.getNumArguments() << " captures where @"
                                 << ctor.name.getValue() << " has " << ctor.fields.size();
  for (auto [arg, field] : llvm::zip_equal(body.getArguments(), ctor.fields))
    if (arg.getType() != atPermission(field, gradeOf(arg.getType()).permission))
      return emitOpError("binds a capture of type ")
             << arg.getType() << " where @" << ctor.name.getValue() << " holds " << field;
  return success();
}

// The region yields the value the cell's forced state holds, at any
// permission, then each result.
LogicalResult MemoRunOp::verifyRegions() {
  DataType memo = getDataType();
  SmallVector<Type> types{memo.getCtor(memo.getForcedTag()).fields.front()};
  llvm::append_range(types, getOuts().getTypes());
  return arrays::verifyEnd(*this, types, [](unsigned at) { return at == 0; });
}

// The region runs once, between the move out and the move in, and what it
// gives after the value leaves the op.
void MemoRunOp::getSuccessorRegions(RegionBranchPoint point,
                                    SmallVectorImpl<RegionSuccessor> &regions) {
  if (point.isParent())
    regions.push_back(RegionSuccessor(&getRegion()));
  else
    regions.push_back(RegionSuccessor(getOperation()));
}

ValueRange MemoRunOp::getSuccessorInputs(RegionSuccessor successor) {
  if (successor.isOperation())
    return getOuts();
  return ValueRange();
}

void MemoRunOp::getRegionInvocationBounds(ArrayRef<Attribute>,
                                          SmallVectorImpl<InvocationBounds> &bounds) {
  bounds.emplace_back(1, 1);
}

// It reads the captures out of the cell and writes its state, in the
// default resource, as an update reads and writes its array's element; the
// region's effects are its own.
void MemoRunOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  OpOperand &cell = getCellMutable();
  effects.emplace_back(MemoryEffects::Read::get(), &cell, SideEffects::DefaultResource::get());
  effects.emplace_back(MemoryEffects::Write::get(), &cell, SideEffects::DefaultResource::get());
}

// Each capture moves out of its field of the label's state into the
// region, with the reference the cell held; the yield moves the value into
// the forced state (idr.array.yield's edges).
void MemoRunOp::getFlowEdges(FlowEdges &edges) {
  Value cell = getCell();
  DataType memo = getDataType();
  for (BlockArgument capture : getCaptures())
    edges.flow(FlowPoint::partOf(cell, FlowAnchor::fieldOf(memo, getTag(), capture.getArgNumber())),
               FlowPoint::of(Value(capture)));
}
