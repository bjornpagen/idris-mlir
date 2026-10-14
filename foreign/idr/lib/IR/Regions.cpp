// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// How control enters and leaves every region op of the dialect: a match
// and an array loop branch into their regions, as region branch ops, and
// the yield that ends a region goes on where its parent says. idr.lambda
// and idr.delay, a closure and a suspension whose body is their region
// until idr-isolate gives it a function of its own, run their body when
// applied or forced, so neither is a region branch.

#include "idr/IR/IdrDialect.h"

#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "mlir/Transforms/RegionUtils.h"

using namespace mlir;
using namespace idr;

namespace {

// A match as a RegionBranchOpInterface, as scf.index_switch: control enters
// exactly one region, which returns to the match. From a region, back to
// the match; from the match, into every region.
void matchSuccessors(Operation *op, RegionBranchPoint point,
                     SmallVectorImpl<RegionSuccessor> &successors) {
  if (!point.isParent()) {
    successors.push_back(RegionSuccessor(op));
    return;
  }
  for (Region &region : op->getRegions())
    successors.emplace_back(&region);
}

// The region `taken`, when the match is known to take it; else every one.
void matchEntrySuccessors(Operation *op, Region *taken,
                          SmallVectorImpl<RegionSuccessor> &successors) {
  if (taken)
    successors.emplace_back(taken);
  else
    matchSuccessors(op, RegionBranchPoint::parent(), successors);
}

// At most once each region, and none but `taken` when it is known.
void matchInvocationBounds(Operation *op, Region *taken,
                           SmallVectorImpl<InvocationBounds> &bounds) {
  for (Region &region : op->getRegions())
    bounds.emplace_back(/*lb=*/0, /*ub=*/!taken || taken == &region ? 1 : 0);
}

// The body and the loop itself. The body is its own successor, so the
// region runs again; the loop is a successor too, because an empty array
// skips the body and a finished iteration leaves. The size is not a
// constant the op can read here, so neither edge is dropped.
void arrayLoopSuccessors(Operation *op, Region &body, SmallVectorImpl<RegionSuccessor> &regions) {
  regions.push_back(RegionSuccessor(&body));
  regions.push_back(RegionSuccessor(op));
}

// The body ends in idr.yield of `results`, or in ub.unreachable after a
// crash. The block is not empty (SingleBlock), so it has an op to end in;
// the yields of the matches inside it are theirs. Neither op is a region
// branch, so no RegionBranchOpInterface edge checks what the yield gives.
LogicalResult verifyEnd(Operation *op, Block &body, TypeRange results) {
  Operation *end = &body.back();
  if (isa<ub::UnreachableOp>(end))
    return success();
  auto yield = dyn_cast<YieldOp>(end);
  if (!yield)
    return op->emitOpError("must end in idr.yield or ub.unreachable");
  if (yield.getResults().getTypes() != results)
    return yield.emitOpError("yields ") << yield.getResults().getTypes() << ", but its "
                                        << op->getName() << " has results " << results;
  return success();
}

} // namespace

//===----------------------------------------------------------------------===//
// The matches
//===----------------------------------------------------------------------===//

void MatchOp::getSuccessorRegions(RegionBranchPoint point,
                                  SmallVectorImpl<RegionSuccessor> &successors) {
  matchSuccessors(*this, point, successors);
}

void MatchOp::getEntrySuccessorRegions(ArrayRef<Attribute> operands,
                                       SmallVectorImpl<RegionSuccessor> &successors) {
  matchEntrySuccessors(*this, getTakenRegion(operands.front()), successors);
}

void MatchOp::getRegionInvocationBounds(ArrayRef<Attribute> operands,
                                        SmallVectorImpl<InvocationBounds> &bounds) {
  matchInvocationBounds(*this, getTakenRegion(operands.front()), bounds);
}

ValueRange MatchOp::getSuccessorInputs(RegionSuccessor successor) {
  return successor.isOperation() ? ValueRange(getResults()) : ValueRange();
}

void MatchLitOp::getSuccessorRegions(RegionBranchPoint point,
                                     SmallVectorImpl<RegionSuccessor> &successors) {
  matchSuccessors(*this, point, successors);
}

void MatchLitOp::getEntrySuccessorRegions(ArrayRef<Attribute> operands,
                                          SmallVectorImpl<RegionSuccessor> &successors) {
  matchEntrySuccessors(*this, getTakenRegion(operands.front()), successors);
}

void MatchLitOp::getRegionInvocationBounds(ArrayRef<Attribute> operands,
                                           SmallVectorImpl<InvocationBounds> &bounds) {
  matchInvocationBounds(*this, getTakenRegion(operands.front()), bounds);
}

ValueRange MatchLitOp::getSuccessorInputs(RegionSuccessor successor) {
  return successor.isOperation() ? ValueRange(getResults()) : ValueRange();
}

//===----------------------------------------------------------------------===//
// The array loops
//===----------------------------------------------------------------------===//

// From outside and from the body alike: the body may run, and the loop may
// be done.
void ArrayGenerateOp::getSuccessorRegions(RegionBranchPoint,
                                          SmallVectorImpl<RegionSuccessor> &regions) {
  arrayLoopSuccessors(*this, getBody(), regions);
}

// Nothing is forwarded. The fill is stored as element 0, and the body
// stores what it yields; neither is an SSA successor.
OperandRange ArrayGenerateOp::getEntrySuccessorOperands(RegionSuccessor) {
  return MutableOperandRange(*this, /*start=*/0, /*length=*/0);
}

void ArrayFoldOp::getSuccessorRegions(RegionBranchPoint,
                                      SmallVectorImpl<RegionSuccessor> &regions) {
  arrayLoopSuccessors(*this, getBody(), regions);
}

// The accumulator the body starts from, and the result of an empty array.
// Both edges take it; the element and the index are not among them.
OperandRange ArrayFoldOp::getEntrySuccessorOperands(RegionSuccessor) {
  return MutableOperandRange(getInitMutable());
}

ValueRange ArrayFoldOp::getSuccessorInputs(RegionSuccessor successor) {
  if (successor.isOperation())
    return getResults().slice(0, 1);
  if (getBody().empty() || getBody().front().getNumArguments() == 0)
    return {};
  return getBody().front().getArguments().slice(0, 1);
}

// The fold's own check compares the accumulator with its grade removed, so
// an owned word and the word are the same value on the edge.
bool ArrayFoldOp::areTypesCompatible(Type lhs, Type rhs) {
  return unrestricted(lhs) == unrestricted(rhs);
}

//===----------------------------------------------------------------------===//
// The yield
//===----------------------------------------------------------------------===//

// A lambda's or a delay's body runs when the closure is applied or the
// suspension forced, not when the op runs, so the yield that ends it goes
// to no region: the op is no region branch.
void YieldOp::getSuccessorRegions(ArrayRef<Attribute>, SmallVectorImpl<RegionSuccessor> &regions) {
  Operation *parent = (*this)->getParentOp();
  if (isa<LambdaOp, DelayOp>(parent))
    return;
  cast<RegionBranchOpInterface>(parent).getSuccessorRegions(
      RegionBranchPoint(cast<RegionBranchTerminatorOpInterface>(getOperation())), regions);
}

// A generate stores the yielded word in the new array. Forwarding it would
// invent an SSA edge the loop does not have. A fold's yield is the next
// accumulator, and a match's yield is the match's results. The successor
// says which: inlining a match moves this terminator into the enclosing
// block before asking what it forwards, and that block may be a generate.
MutableOperandRange YieldOp::getMutableSuccessorOperands(RegionSuccessor successor) {
  Operation *target = successor.isOperation() ? successor.getSuccessorOp()
                                              : successor.getSuccessor()->getParentOp();
  if (isa_and_nonnull<ArrayGenerateOp>(target))
    return MutableOperandRange(*this, /*start=*/0, /*length=*/0);
  return MutableOperandRange(*this);
}

//===----------------------------------------------------------------------===//
// idr.lambda and idr.delay
//===----------------------------------------------------------------------===//

// The block is the body of the function the closure is of: it takes the
// closure's parameters and yields its results.
LogicalResult LambdaOp::verify() {
  FnType type = getType();
  Block &body = getBody().front();
  if (body.getArgumentTypes() != type.getInputs())
    return emitOpError("takes ") << body.getArgumentTypes() << ", but its type " << type
                                 << " takes " << type.getInputs();
  return success();
}

LogicalResult LambdaOp::verifyRegions() {
  return verifyEnd(getOperation(), getBody().front(), getType().getResults());
}

// A force passes nothing, so the block takes nothing, and yields the
// suspension's value. A world passes only as an argument or a result, never
// into a suspension, so the body uses none from above.
LogicalResult DelayOp::verify() {
  Block &body = getBody().front();
  if (body.getNumArguments() != 0)
    return emitOpError("takes ") << body.getArgumentTypes()
                                 << ", but a suspension's body takes nothing";
  return success();
}

LogicalResult DelayOp::verifyRegions() {
  Type value = cast<LazyType>(unrestricted(getType())).getValue();
  if (failed(verifyEnd(getOperation(), getBody().front(), value)))
    return failure();
  bool worldAbove = false;
  visitUsedValuesDefinedAbove(getBody(), getBody(), [&](OpOperand *use) {
    worldAbove = worldAbove || isWorld(use->get().getType());
  });
  if (worldAbove)
    return emitOpError("uses a world from above; a world passes only as an argument or result");
  return success();
}
