// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The ops on mutable memory (new, get, set, update), with their rules,
// shapes and how an element moves; the read of a value array that gives the
// array back; the three movements a step of a generating op on buffers
// makes (take, copy, place); the extent of an array to be made; the tie of
// an array's dimensions to sizes, with what value bounds and the folding
// of a dimension read from it; and the skeleton rule that makes a read and
// a write of one element its update.
//
// Mutable memory is base's IOArray, Buffer and IORef: a buffer in the
// memory space #idr.mutable, written after it is shared. A value array's
// buffer, which bufferization makes of a tensor, is in the default memory
// space and written only where One-Shot proved the write in place, so no
// type is both. Every access takes one `index` per dimension, as
// upstream's memref ops do.

#include "idr/IR/Arrays.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Ranges.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Dialect/Utils/StaticValueUtils.h"
#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/SmallPtrSet.h"

// What each stage of a program implies: whether its holds are decided.
#include "idr/IR/Generated/StageFacts.h.inc"

// The runtime's C ABI: the largest small natural.
#include "idris_rt.h"

using namespace mlir;
using namespace idr;
using namespace idr::arrays;

namespace {

// An access takes one index per dimension of its buffer, and a new array
// one size: what memref.load and memref.alloc ask of theirs.
LogicalResult verifyCount(Operation *op, size_t count, StringRef what, MemRefType array) {
  if (count != static_cast<size_t>(array.getRank()))
    return op->emitOpError("takes ") << count << " " << what << " for an array of rank "
                                     << array.getRank();
  return success();
}

// An element moves into a buffer, or out of it, at the buffer's element
// type, the grade it carries aside.
LogicalResult verifyElement(Operation *op, StringRef what, Type type, MemRefType array) {
  if (unrestricted(type) != array.getElementType())
    return op->emitOpError() << what << " has type " << type << ", but the array holds "
                             << array.getElementType();
  return success();
}

// A movement at `indices` of a buffer moves what its slots there hold: an
// element at as many indices as the buffer has dimensions, else the cell
// under them, a buffer of the identity layout.
LogicalResult verifyMoved(Operation *op, Type moved, MemRefType buffer, size_t indices) {
  if (indices > static_cast<size_t>(buffer.getRank()))
    return op->emitOpError("takes ") << indices << " indices for a buffer of rank "
                                     << buffer.getRank();
  Type expected = cellOf(buffer, static_cast<unsigned>(indices));
  if (moved != expected)
    return op->emitOpError("moves ") << moved << " where the buffer holds " << expected
                                     << " at " << indices << " indices";
  return success();
}

// Whether an effect may reach memory written in place: a read, a write or
// a release on contents or on a state above it. An allocation names a
// fresh value, which nothing else reaches.
bool onContents(const effects::Effect &each) {
  return each.kind != effects::Kind::Allocate &&
         effects::atOrAbove[effects::ResourceId::Contents].contains(each.resource);
}

// Whether `op`, with everything in it, may touch memory written in place,
// or does what MLIR cannot say: what no op inside an update's region may
// do, since the element's place is empty while it runs.
bool touchesInPlace(Operation *op) {
  return effects::classify(op, onContents) == effects::Does::Touches;
}

} // namespace

namespace idr {

// A value array's buffer is in the default memory space, which no mutable
// memory is in.
bool isValueBuffer(Type type) {
  auto buffer = dyn_cast<MemRefType>(unrestricted(type));
  return buffer && !buffer.getMemorySpace();
}

} // namespace idr

//===----------------------------------------------------------------------===//
// Mutable memory
//===----------------------------------------------------------------------===//

LogicalResult ArrayNewOp::verify() {
  auto type = cast<MemRefType>(unrestricted(getArray().getType()));
  if (failed(verifyCount(*this, getSizes().size(), "sizes", type)))
    return failure();
  return verifyElement(*this, "the fill", getFill().getType(), type);
}

LogicalResult ArrayGetOp::verify() {
  auto type = cast<MemRefType>(unrestricted(getArray().getType()));
  if (failed(verifyCount(*this, getIndices().size(), "indices", type)))
    return failure();
  return verifyElement(*this, "the result", getValue().getType(), type);
}

LogicalResult ArraySetOp::verify() {
  auto type = cast<MemRefType>(unrestricted(getArray().getType()));
  if (failed(verifyCount(*this, getIndices().size(), "indices", type)))
    return failure();
  return verifyElement(*this, "the value", getValue().getType(), type);
}

// Each dimension of the new array is its size: the frontend gives a size
// below zero as zero before it is an index.
LogicalResult ArrayNewOp::reifyResultShapes(OpBuilder &, ReifiedRankedShapedTypeDims &shapes) {
  shapes.push_back(getAsOpFoldResult(getSizes()));
  return success();
}

// An element moves in through the fill, which every element holds, and
// through a write, which releases the element it replaces; a read borrows
// it, the reference a reader keeps being counting's to take.
void ArrayNewOp::getFlowEdges(FlowEdges &edges) {
  edges.flow(FlowPoint::of(getFillMutable()), elementsOf(getArray()));
  edges.fresh(getArray());
}
void ArrayGetOp::getFlowEdges(FlowEdges &edges) {
  edges.flow(elementsOf(getArray()), FlowPoint::of(getValue()));
}
void ArraySetOp::getFlowEdges(FlowEdges &edges) {
  edges.flow(FlowPoint::of(getValueMutable()), elementsOf(getArray()));
  edges.overwrite(elementsOf(getArray()));
}

//===----------------------------------------------------------------------===//
// idr.array.update
//===----------------------------------------------------------------------===//

// One index per dimension of the buffer, and a region that binds the
// element alone, at the buffer's element type at any grade.
LogicalResult ArrayUpdateOp::verify() {
  auto type = cast<MemRefType>(unrestricted(getArray().getType()));
  if (failed(verifyCount(*this, getIndices().size(), "indices", type)))
    return failure();
  Block &body = getRegion().front();
  if (body.getNumArguments() != 1)
    return emitOpError("binds ") << body.getNumArguments()
                                 << " values in its region, where it binds the element alone";
  return verifyElement(*this, "the element", body.getArgument(0).getType(), type);
}

// Between the element's move out and its move back, its place holds
// nothing, and only the region runs there. So the region reads and writes
// no memory written in place: no access it makes can see the empty place.
// Asked of the region's effects, its calls' rows among them.
LogicalResult ArrayUpdateOp::verifyRegions() {
  if (auto end = dyn_cast<ArrayUpdateYieldOp>(getRegion().front().getTerminator())) {
    auto type = cast<MemRefType>(unrestricted(getArray().getType()));
    if (unrestricted(end.getElement().getType()) != type.getElementType())
      return end.emitOpError("gives back ") << end.getElement().getType()
                                            << " for an element of " << type.getElementType();
    if (end.getOuts().getTypes() != getOuts().getTypes())
      return end.emitOpError("gives ") << end.getOuts().getTypes() << " where the update gives "
                                       << getOuts().getTypes();
  }
  for (Operation &inner : getRegion().front().without_terminator())
    if (touchesInPlace(&inner))
      return inner.emitOpError("may touch memory written in place inside an update's region");
  return success();
}

void ArrayUpdateOp::getSuccessorRegions(RegionBranchPoint point,
                                        SmallVectorImpl<RegionSuccessor> &regions) {
  if (point.isParent())
    regions.push_back(RegionSuccessor(&getRegion()));
  else
    regions.push_back(RegionSuccessor(getOperation()));
}

ValueRange ArrayUpdateOp::getSuccessorInputs(RegionSuccessor successor) {
  if (successor.isOperation())
    return getOuts();
  return ValueRange();
}

void ArrayUpdateOp::getRegionInvocationBounds(ArrayRef<Attribute>,
                                              SmallVectorImpl<InvocationBounds> &bounds) {
  bounds.emplace_back(1, 1);
}

// The element moves out of its place into the region, whose end moves the
// rebuilt one back in.
void ArrayUpdateOp::getFlowEdges(FlowEdges &edges) {
  edges.flow(elementsOf(getArray()), FlowPoint::of(getRegion().front().getArgument(0)));
}

ValueRange ArrayUpdateOp::getYieldTargets() { return getODSOperands(0); }

// The values after the element leave the update as its results.
MutableOperandRange ArrayUpdateYieldOp::getMutableSuccessorOperands(RegionSuccessor) {
  return getOutsMutable();
}

// The rebuilt element moves back into its place.
void ArrayUpdateYieldOp::getFlowEdges(FlowEdges &edges) {
  auto update = cast<ArrayUpdateOp>((*this)->getParentOp());
  edges.flow(FlowPoint::of(getElementMutable()), elementsOf(update.getArray()));
}

//===----------------------------------------------------------------------===//
// idr.array.read
//===----------------------------------------------------------------------===//

// One index per dimension, the element of the array's element type, and
// the array given back as it was: a new value of the same array, which
// whatever writes it next consumes, so that the read precedes the write by
// the data it reads and not by where it stands.
LogicalResult ArrayReadOp::verify() {
  auto type = cast<RankedTensorType>(getArray().getType());
  if (getIndices().size() != static_cast<size_t>(type.getRank()))
    return emitOpError("takes ") << getIndices().size() << " indices for an array of rank "
                                 << type.getRank();
  if (getValue().getType() != type.getElementType())
    return emitOpError("reads ") << getValue().getType() << " from an array of "
                                 << type.getElementType();
  return success();
}

// The array given back is the array; the element is borrowed from it, the
// reference a reader keeps being counting's to take.
void ArrayReadOp::getFlowEdges(FlowEdges &edges) {
  edges.flow(FlowPoint::of(getArrayMutable()), FlowPoint::of(getAfter()));
  edges.flow(elementsOf(getArray()), FlowPoint::of(getValue()));
}

//===----------------------------------------------------------------------===//
// The movements of a step on buffers
//===----------------------------------------------------------------------===//

LogicalResult ArrayTakeOp::verify() {
  return verifyMoved(*this, getValue().getType(), cast<MemRefType>(getBuffer().getType()),
                     getIndices().size());
}

LogicalResult ArrayCopyOp::verify() {
  return verifyMoved(*this, getValue().getType(), cast<MemRefType>(getBuffer().getType()),
                     getIndices().size());
}

LogicalResult ArrayPlaceOp::verify() {
  return verifyMoved(*this, getValue().getType(), cast<MemRefType>(getBuffer().getType()),
                     getIndices().size());
}

// A take moves what the slots hold out, which leaves them holding nothing;
// a copy reads it with references of its own; a place moves a value in.
void ArrayTakeOp::getFlowEdges(FlowEdges &edges) {
  edges.flow(elementsOf(getBuffer()), atIndex(getValue()));
  edges.overwrite(elementsOf(getBuffer()));
}
void ArrayCopyOp::getFlowEdges(FlowEdges &edges) {
  edges.flow(elementsOf(getBuffer()), atIndex(getValue()));
  edges.fresh(getValue());
}
void ArrayPlaceOp::getFlowEdges(FlowEdges &edges) {
  edges.flow(atIndex(getValueMutable()), elementsOf(getBuffer()));
}

//===----------------------------------------------------------------------===//
// The extent of an array to be made
//===----------------------------------------------------------------------===//

// A constant natural that is small is its extent. One that is not stays,
// to end the run as out of memory where it runs: no allocation of that
// many elements can be made.
OpFoldResult NatToExtentOp::fold(FoldAdaptor adaptor) {
  auto big = dyn_cast_or_null<BigAttr>(adaptor.getNatural());
  if (!big)
    return {};
  const APInt &value = big.getValue();
  if (value.isNegative() || value.getSignificantBits() > 64 ||
      value.getSExtValue() > IDRIS_RT_SMALL_MAX)
    return {};
  return IntegerAttr::get(IndexType::get(getContext()), value.getSExtValue());
}

// The natural's range, within what the op lets through: 0 to the largest
// small.
void NatToExtentOp::inferResultRanges(ArrayRef<ConstantIntRanges> ranges,
                                      SetIntRangeFn setResultRange) {
  idr::ranges::Bounds bounds = idr::ranges::boundsOf(ranges[0]);
  int64_t lo = std::max<int64_t>(bounds.lo.value_or(0), 0);
  int64_t hi = std::min<int64_t>(bounds.hi.value_or(IDRIS_RT_SMALL_MAX), IDRIS_RT_SMALL_MAX);
  if (hi < lo)
    hi = lo;
  setResultRange(getResult(), ConstantIntRanges::fromSigned(
                                  APInt(64, static_cast<uint64_t>(lo), /*isSigned=*/true),
                                  APInt(64, static_cast<uint64_t>(hi), /*isSigned=*/true)));
}

//===----------------------------------------------------------------------===//
// Dimensions across calls
//===----------------------------------------------------------------------===//

// One size per dynamic dimension.
LogicalResult ArrayTieShapeOp::verify() {
  auto type = cast<ShapedType>(getType());
  if (getDims().size() != static_cast<size_t>(type.getNumDynamicDims()))
    return emitOpError("takes ") << getDims().size() << " sizes for " << type
                                 << ", which has " << type.getNumDynamicDims()
                                 << " dynamic dimensions";
  return success();
}

Value ArrayTieShapeOp::getViewSource() { return getValue(); }

// No dynamic dimension, nothing to say; the same sizes said twice, once.
OpFoldResult ArrayTieShapeOp::fold(FoldAdaptor) {
  if (getDims().empty())
    return getValue();
  if (auto inner = getValue().getDefiningOp<ArrayTieShapeOp>();
      inner && inner.getDims() == getDims())
    return getValue();
  return {};
}

// Each dimension: a static one's size, a dynamic one's operand.
LogicalResult ArrayTieShapeOp::reifyResultShapes(OpBuilder &b,
                                                 ReifiedRankedShapedTypeDims &shapes) {
  auto type = cast<ShapedType>(getType());
  SmallVector<OpFoldResult> dims;
  unsigned next = 0;
  for (int64_t size : type.getShape())
    dims.push_back(ShapedType::isDynamic(size) ? OpFoldResult(getDims()[next++])
                                               : OpFoldResult(b.getIndexAttr(size)));
  shapes.push_back(std::move(dims));
  return success();
}

// The result's dimension is its size, and is the operand's: so two arrays
// tied to one size have one dimension, wherever each came from.
void ArrayTieShapeOp::populateBoundsForShapedValueDim(Value value, int64_t dim,
                                                 ValueBoundsConstraintSet &cstr) {
  auto type = cast<ShapedType>(getType());
  auto at = static_cast<unsigned>(dim);
  if (type.isDynamicDim(at))
    cstr.bound(value)[dim] == OpFoldResult(getDims()[type.getDynamicDimIndex(at)]);
  else
    cstr.bound(value)[dim] == type.getDimSize(at);
  cstr.bound(value)[dim] == cstr.getExpr(getValue(), dim);
}

//===----------------------------------------------------------------------===//
// A read and a write of one element: its update
//===----------------------------------------------------------------------===//

namespace {

// A write of one element and the read it pairs with, read through the same
// questions: ours on mutable memory, upstream's on a value array's buffer.
template <class Write>
struct ElementAccess;

template <>
struct ElementAccess<ArraySetOp> {
  using Read = ArrayGetOp;
  static Value array(ArrayGetOp read) { return read.getArray(); }
  static Value array(ArraySetOp write) { return write.getArray(); }
  static Value element(ArrayGetOp read) { return read.getValue(); }
  static Value written(ArraySetOp write) { return write.getValue(); }
};

template <>
struct ElementAccess<memref::StoreOp> {
  using Read = memref::LoadOp;
  static Value array(memref::LoadOp read) { return read.getMemref(); }
  static Value array(memref::StoreOp write) { return write.getMemref(); }
  static Value element(memref::LoadOp read) { return read.getResult(); }
  static Value written(memref::StoreOp write) { return write.getValueToStore(); }
};

template <class Write>
concept ElementWrite = requires { typename ElementAccess<Write>::Read; };

// What a write and the read of its element become: the read, the ops
// between that rebuild the element from it, in order, and the values still
// read after the write, the element's or the rebuilding's.
template <ElementWrite Write>
struct Fusion {
  typename ElementAccess<Write>::Read read;
  SmallVector<Operation *> rebuilding;
  SmallVector<Value> leaving;
};

// An index as the value it was checked from: a guard gives its operand.
Value unguarded(Value index) {
  return definitionChain(index, [](Value value) -> std::optional<Value> {
           if (auto guard = value.getDefiningOp<GuardOpInterface>())
             return guard.getGuarded();
           return std::nullopt;
         }).back();
}

// Whether two indices are one: the same value or the same constant,
// whichever guard checked it.
bool sameIndex(Value a, Value b) { return isEqualConstantIntOrValue(unguarded(a), unguarded(b)); }

// Whether the program `op` stands in counts no reference yet: its holds are
// undecided, as they are at every stage before lifetimes are decided. The
// stage is the program's, which a pass at any stage meets only as it runs.
bool uncounted(Operation *op) {
  ProgramOp program = op->getParentOfType<FuncOp>().getProgram();
  return holdsAt[program.getStage()] == StageHolds::Undecided;
}

// The fusion of `write` with the read of its element, or nothing.
template <ElementWrite Write>
std::optional<Fusion<Write>> fusionOf(Write write) {
  using Access = ElementAccess<Write>;
  auto array = cast<MemRefType>(unrestricted(Access::array(write).getType()));
  // An element that holds no reference has none to give up.
  if (!holdsReferences(array.getElementType()) || !uncounted(write))
    return std::nullopt;
  // Memory of the array is a buffer of its element in its memory space,
  // whatever its shape, layout or grade, as a view of it is.
  auto touchesArray = [array](const effects::Effect &each) {
    if (!onContents(each))
      return false;
    if (!each.value)
      return true;
    auto buffer = dyn_cast<BaseMemRefType>(unrestricted(each.value.getType()));
    return buffer && buffer.getElementType() == array.getElementType() &&
           buffer.getMemorySpace() == array.getMemorySpace();
  };
  // The read is the last op before the write that may touch memory of the
  // array, so nothing between does; `between` holds the ops between, the
  // nearest the write first.
  SmallVector<Operation *> between;
  Operation *last = write->getPrevNode();
  for (; last && effects::classify(last, touchesArray) != effects::Does::Touches;
       last = last->getPrevNode())
    between.push_back(last);
  auto read = dyn_cast_or_null<typename Access::Read>(last);
  if (!read || arrayRoot(Access::array(read)) != arrayRoot(Access::array(write)) ||
      !llvm::equal(read.getIndices(), write.getIndices(), sameIndex))
    return std::nullopt;

  // The rebuilding, in order: each op between that reads the element, or a
  // value of the rebuilding, anywhere in it. It moves into the update's
  // region, where the element's place is empty.
  Fusion<Write> fusion{read, {}, {}};
  Value element = Access::element(read);
  llvm::SmallPtrSet<Operation *, 8> rebuilds;
  auto readsRebuilt = [&](Operation *op) {
    return op
        ->walk([&](Operation *inner) {
          bool reads = llvm::any_of(inner->getOperands(), [&](Value operand) {
            Operation *def = operand.getDefiningOp();
            return operand == element || (def && rebuilds.contains(def));
          });
          return reads ? WalkResult::interrupt() : WalkResult::advance();
        })
        .wasInterrupted();
  };
  for (Operation *op : llvm::reverse(between)) {
    if (!readsRebuilt(op))
      continue;
    if (touchesInPlace(op))
      return std::nullopt;
    rebuilds.insert(op);
    fusion.rebuilding.push_back(op);
  }

  // Each op of the rebuilding moves to the write past the ops between after
  // it that stay, which neither may tell.
  effects::EffectSet staying;
  for (Operation *op : between) {
    effects::EffectSet does = effects::whole(op);
    if (!rebuilds.contains(op))
      staying = staying | does;
    else if (does.conflicts(staying))
      return std::nullopt;
  }

  // What leaves the update: the element and the rebuilding's values that an
  // op after the write reads, the write itself aside.
  Block *block = write->getBlock();
  auto readAfter = [&](Value value) {
    return llvm::any_of(value.getUses(), [&](OpOperand &use) {
      Operation *at = block->findAncestorOpInBlock(*use.getOwner());
      return at != write.getOperation() && !rebuilds.contains(at);
    });
  };
  if (readAfter(element))
    fusion.leaving.push_back(element);
  for (Operation *op : fusion.rebuilding)
    for (Value result : op->getResults())
      if (readAfter(result))
        fusion.leaving.push_back(result);
  return fusion;
}

// The update in the write's place: the rebuilding moved into its region in
// order, the element its region's argument there, the value written given
// back into the element's place, and every value that leaves read from the
// update's results after it.
template <ElementWrite Write>
void fuse(RewriterBase &rewriter, Write write, const Fusion<Write> &fusion) {
  using Access = ElementAccess<Write>;
  Value element = Access::element(fusion.read);
  Location loc = rewriter.getFusedLoc({fusion.read.getLoc(), write.getLoc()});
  rewriter.setInsertionPoint(write);
  auto update = ArrayUpdateOp::create(rewriter, loc, ValueRange(fusion.leaving).getTypes(),
                                      Access::array(write), write.getIndices());
  Block *body =
      rewriter.createBlock(&update.getRegion(), {}, {element.getType()}, {fusion.read.getLoc()});
  for (Operation *op : fusion.rebuilding)
    rewriter.moveOpBefore(op, body, body->end());
  Value moving = body->getArgument(0);
  rewriter.replaceUsesWithIf(element, moving, [&](OpOperand &use) {
    return update->isProperAncestor(use.getOwner());
  });
  auto inside = [&](Value value) { return value == element ? moving : value; };
  rewriter.setInsertionPointToEnd(body);
  ArrayUpdateYieldOp::create(rewriter, loc, inside(Access::written(write)),
                             llvm::map_to_vector(fusion.leaving, inside));
  for (auto [value, out] : llvm::zip_equal(fusion.leaving, update.getOuts()))
    rewriter.replaceUsesWithIf(value, out, [&](OpOperand &use) {
      return use.getOwner() != write.getOperation() && !update->isAncestor(use.getOwner());
    });
  rewriter.eraseOp(write);
  rewriter.eraseOp(fusion.read);
}

} // namespace

void idr::arrays::moveOut(RewriterBase &rewriter, memref::StoreOp write) {
  if (std::optional<Fusion<memref::StoreOp>> fusion = fusionOf(write))
    fuse(rewriter, write, *fusion);
}

namespace idr::egraph {

// The fusion is the IR's, read off effects; the e-graph's facts add
// nothing to it.
std::optional<Edit> MoveOut::decide(ArraySetOp write, const OperandFacts &) {
  if (!fusionOf(write))
    return std::nullopt;
  return Rewrite{};
}

// The fusion found again on the input as it now is, since an earlier
// rewrite may have changed what stands before the write.
void MoveOut::rewrite(ArraySetOp write, const Rewrite &, RewriterBase &rewriter) {
  if (std::optional<Fusion<ArraySetOp>> fusion = fusionOf(write))
    fuse(rewriter, write, *fusion);
}

} // namespace idr::egraph
