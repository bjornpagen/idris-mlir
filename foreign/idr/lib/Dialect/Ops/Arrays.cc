// The ops on arrays: new, get, set, and the loops generate and fold.

#include "idr/Idr.h"

#include "mlir/IR/OpImplementation.h"

import idr.ops;

using namespace mlir;
using namespace idr;

namespace {

// The body and the loop itself. The body is its own successor, so the
// region runs again; the loop is a successor too, because an empty array
// skips the body and a finished iteration leaves. The size is not a
// constant the op can read here, so neither edge is dropped.
void arrayLoopSuccessors(Operation *op, Region &body, SmallVectorImpl<RegionSuccessor> &regions) {
  regions.push_back(RegionSuccessor(&body));
  regions.push_back(RegionSuccessor(op));
}

// An access takes one index per dimension of its array, and a new array one
// size: what memref.load and memref.alloc ask of theirs.
LogicalResult verifyCount(Operation *op, size_t count, StringRef what, MemRefType array) {
  if (count != static_cast<size_t>(array.getRank()))
    return op->emitOpError("takes ") << count << " " << what << " for an array of rank "
                                     << array.getRank();
  return success();
}

// An index as its access's guard was given it: the guard's result is the
// value it checked.
Value unguarded(Value index) {
  if (auto guard = index.getDefiningOp<CheckInBoundsOp>())
    return guard.getIndex();
  return index;
}

} // namespace

bool idr::sameElement(Value array, ValueRange indices, Value otherArray, ValueRange otherIndices) {
  return arrayRoot(array) == arrayRoot(otherArray) &&
         llvm::equal(indices, otherIndices,
                     [](Value x, Value y) { return unguarded(x) == unguarded(y); });
}

LogicalResult ArrayNewOp::verify() {
  if (failed(verifyCount(*this, getSizes().size(), "sizes", getArrayType())))
    return failure();
  return ops::verifyElement(*this, "the fill", getFill().getType(), getArrayType());
}

// A read that moves its element out leaves the element's place empty, so
// the next IO on its world, its world's one use, is the write that fills
// that place again, in its block: an element that holds no reference has
// nothing to move, and anything else between would see the empty place.
LogicalResult ArrayGetOp::verify() {
  if (failed(verifyCount(*this, getIndices().size(), "indices", getArrayType())))
    return failure();
  if (getMoves()) {
    SymbolTableCollection symbols;
    if (!holdsReferences(getArrayType().getElementType(), symbols, *this))
      return emitOpError("moves out an element that holds no reference");
    auto set = getNext().hasOneUse() ? dyn_cast<ArraySetOp>(*getNext().getUsers().begin())
                                     : ArraySetOp();
    if (!set || set->getBlock() != (*this)->getBlock() ||
        !sameElement(getArray(), getIndices(), set.getArray(), set.getIndices()))
      return emitOpError("moves its element out, but its world does not go next to a write of "
                         "that element in its block");
  }
  return ops::verifyElement(*this, "the result", getValue().getType(), getArrayType());
}

LogicalResult ArraySetOp::verify() {
  if (failed(verifyCount(*this, getIndices().size(), "indices", getArrayType())))
    return failure();
  return ops::verifyElement(*this, "the value", getValue().getType(), getArrayType());
}

// Each dimension of the new array is its size clamped at 0, as an index:
// the length idris_rt_array_new gives a negative size. An array of rank 0
// has none. The world result has no shape.
LogicalResult ArrayNewOp::reifyResultShapes(OpBuilder &b,
                                            ReifiedRankedShapedTypeDims &shapes) {
  Location loc = getLoc();
  SmallVector<OpFoldResult> dims;
  for (Value size : getSizes()) {
    Value zero = arith::ConstantOp::create(b, loc, b.getI64IntegerAttr(0));
    Value length = arith::MaxSIOp::create(b, loc, size, zero);
    dims.push_back(arith::IndexCastOp::create(b, loc, b.getIndexType(), length).getResult());
  }
  shapes.push_back(std::move(dims));
  return success();
}

// IO in the world's order, and for a new array its allocation. An access
// crashes on no index: the index is its guard's to check.
void ArrayNewOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  ops::ioEffects(getArray(), effects);
}
void ArrayGetOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  ops::ioEffects(Value(), effects);
}
void ArraySetOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  ops::ioEffects(Value(), effects);
}

// `idr.array.generate %n, %fill, %w : E -> memref<?xE> (%i: i64) {...}`
ParseResult ArrayGenerateOp::parse(OpAsmParser &parser, OperationState &result) {
  OpAsmParser::UnresolvedOperand size, fill, worldOperand;
  Type fillType, arrayType;
  if (parser.parseOperand(size) || parser.parseComma() || parser.parseOperand(fill) ||
      parser.parseComma() || parser.parseOperand(worldOperand) ||
      parser.parseOptionalAttrDict(result.attributes) || parser.parseColon() ||
      parser.parseType(fillType) || parser.parseArrow() || parser.parseType(arrayType) ||
      ops::parseLoopBody(parser, result))
    return failure();
  Builder &b = parser.getBuilder();
  Type worldType = world(b.getContext());
  if (parser.resolveOperand(size, b.getI64Type(), result.operands) ||
      parser.resolveOperand(fill, fillType, result.operands) ||
      parser.resolveOperand(worldOperand, worldType, result.operands))
    return failure();
  result.addTypes({arrayType, worldType});
  return success();
}

void ArrayGenerateOp::print(OpAsmPrinter &printer) {
  printer << ' ' << getSize() << ", " << getFill() << ", " << getWorld();
  printer.printOptionalAttrDict((*this)->getAttrs());
  printer << " : " << getFill().getType() << " -> " << getArray().getType();
  ops::printLoopBody(printer, getBody());
}

// The body takes the index, an i64.
LogicalResult ArrayGenerateOp::verify() {
  Type element = getArrayType().getElementType();
  if (failed(ops::verifyWord(*this, "the element", element)) ||
      failed(ops::verifyElement(*this, "the fill", getFill().getType(), getArrayType())))
    return failure();
  Type index = IntegerType::get(getContext(), 64);
  TypeRange args = getBody().front().getArgumentTypes();
  if (args != TypeRange(index))
    return emitOpError("expects its body to take ") << TypeRange(index) << ", not " << args;
  return success();
}

// The body yields the element at its index, at any grade. The loop stores
// it and forwards nothing, so no RegionBranchOpInterface edge checks it.
LogicalResult ArrayGenerateOp::verifyRegions() {
  if (failed(ops::verifyLoopEnd(*this, getBody())))
    return failure();
  Type element = getArrayType().getElementType();
  auto yield = dyn_cast<YieldOp>(getBody().front().getTerminator());
  if (yield &&
      (yield.getNumOperands() != 1 || unrestricted(yield.getOperand(0).getType()) != element))
    return yield.emitOpError("yields ")
           << yield.getOperandTypes() << ", but the loop's body gives " << element;
  return success();
}

// `idr.array.fold %a, %init, %w : memref<?xE>, T -> T (%acc: T, %x: E, %i: i64) {...}`
ParseResult ArrayFoldOp::parse(OpAsmParser &parser, OperationState &result) {
  OpAsmParser::UnresolvedOperand array, init, worldOperand;
  Type arrayType, initType, resultType;
  if (parser.parseOperand(array) || parser.parseComma() || parser.parseOperand(init) ||
      parser.parseComma() || parser.parseOperand(worldOperand) ||
      parser.parseOptionalAttrDict(result.attributes) || parser.parseColon() ||
      parser.parseType(arrayType) || parser.parseComma() || parser.parseType(initType) ||
      parser.parseArrow() || parser.parseType(resultType) ||
      ops::parseLoopBody(parser, result))
    return failure();
  Type worldType = world(parser.getBuilder().getContext());
  if (parser.resolveOperand(array, arrayType, result.operands) ||
      parser.resolveOperand(init, initType, result.operands) ||
      parser.resolveOperand(worldOperand, worldType, result.operands))
    return failure();
  result.addTypes({resultType, worldType});
  return success();
}

void ArrayFoldOp::print(OpAsmPrinter &printer) {
  printer << ' ' << getArray() << ", " << getInit() << ", " << getWorld();
  printer.printOptionalAttrDict((*this)->getAttrs());
  printer << " : " << getArray().getType() << ", " << getInit().getType() << " -> "
          << getResult().getType();
  ops::printLoopBody(printer, getBody());
}

LogicalResult ArrayFoldOp::verify() {
  Type element = getArrayType().getElementType();
  Type acc = unrestricted(getInit().getType());
  if (failed(ops::verifyWord(*this, "the element", element)) ||
      failed(ops::verifyWord(*this, "the accumulator", acc)))
    return failure();
  if (unrestricted(getResult().getType()) != acc)
    return emitOpError("gives ") << getResult().getType() << ", but folds an accumulator of "
                                 << acc;
  // The body's three arguments are its region's constraint, which the
  // generated verifier checks before this one.
  Block &block = getBody().front();
  TypeRange args = block.getArgumentTypes();
  if (unrestricted(args[0]) != acc || unrestricted(args[1]) != element || !args[2].isInteger(64))
    return emitOpError("expects its body to take the accumulator (")
           << acc << "), the element (" << element << ") and the index (i64), not " << args;
  return success();
}

// The body yields the next accumulator, which RegionBranchOpInterface
// checks along the yield's edges, back into the body and out to the result.
LogicalResult ArrayFoldOp::verifyRegions() { return ops::verifyLoopEnd(*this, getBody()); }

// As a new array's: its size clamped at 0, as an index.
LogicalResult ArrayGenerateOp::reifyResultShapes(OpBuilder &b,
                                                 ReifiedRankedShapedTypeDims &shapes) {
  Location loc = getLoc();
  Value zero = arith::ConstantOp::create(b, loc, b.getI64IntegerAttr(0));
  Value length = arith::MaxSIOp::create(b, loc, getSize(), zero);
  Value index = arith::IndexCastOp::create(b, loc, b.getIndexType(), length);
  shapes.push_back({OpFoldResult(index)});
  return success();
}

// The loop's own effects: IO in the world's order, and for a generate the
// new array; its body's ops carry theirs (RecursiveMemoryEffects).
void ArrayGenerateOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  ops::ioEffects(getArray(), effects);
}
void ArrayFoldOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  ops::ioEffects(Value(), effects);
}

// RegionBranchOpInterface. From outside and from the body alike: the body
// may run, and the loop may be done.
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
