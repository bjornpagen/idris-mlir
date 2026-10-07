// The ops on arrays: new, get, set, and the loops generate and fold.

#include "idr/Idr.h"

#include "mlir/IR/OpImplementation.h"

import idr.ops;

using namespace mlir;
using namespace idr;

namespace {

// An index is a value the program computed, so it may be out of bounds,
// unless idr-in-bounds proved the access in bounds.
constexpr StringRef outOfBounds = "array index out of bounds";

// The body and the loop itself. The body is its own successor, so the
// region runs again; the loop is a successor too, because an empty array
// skips the body and a finished iteration leaves. The size is not a
// constant the op can read here, so neither edge is dropped.
void arrayLoopSuccessors(Operation *op, Region &body, SmallVectorImpl<RegionSuccessor> &regions) {
  regions.push_back(RegionSuccessor(&body));
  regions.push_back(RegionSuccessor(op));
}

} // namespace

LogicalResult ArrayNewOp::verify() {
  return ops::verifyElement(*this, "the fill", getFill().getType(), getArrayType());
}

LogicalResult ArrayGetOp::verify() {
  return ops::verifyElement(*this, "the result", getValue().getType(), getArrayType());
}

LogicalResult ArraySetOp::verify() {
  return ops::verifyElement(*this, "the value", getValue().getType(), getArrayType());
}

// The one dimension of the new array is its size clamped at 0, as an
// index: the length idris_rt_array_new gives a negative size. The world
// result has no shape.
LogicalResult ArrayNewOp::reifyResultShapes(OpBuilder &b,
                                            ReifiedRankedShapedTypeDims &shapes) {
  Location loc = getLoc();
  Value zero = arith::ConstantOp::create(b, loc, b.getI64IntegerAttr(0));
  Value length = arith::MaxSIOp::create(b, loc, getSize(), zero);
  Value index = arith::IndexCastOp::create(b, loc, b.getIndexType(), length);
  shapes.push_back({OpFoldResult(index)});
  return success();
}

std::optional<StringRef> ArrayNewOp::getCrashCause() { return std::nullopt; }
std::optional<StringRef> ArrayGetOp::getCrashCause() {
  return getInBounds() ? std::nullopt : std::optional(outOfBounds);
}
std::optional<StringRef> ArraySetOp::getCrashCause() {
  return getInBounds() ? std::nullopt : std::optional(outOfBounds);
}

void ArrayNewOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  ops::ioEffects(getCrashCause(), getArray(), effects);
}
void ArrayGetOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  ops::ioEffects(getCrashCause(), Value(), effects);
}
void ArraySetOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  ops::ioEffects(getCrashCause(), Value(), effects);
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

LogicalResult ArrayGenerateOp::verify() {
  Type element = getArrayType().getElementType();
  if (failed(ops::verifyWord(*this, "the element", element)) ||
      failed(ops::verifyElement(*this, "the fill", getFill().getType(), getArrayType())))
    return failure();
  return ops::verifyLoopBody(*this, getBody(), TypeRange{IntegerType::get(getContext(), 64)},
                             element);
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
  Block &block = getBody().front();
  TypeRange args = block.getArgumentTypes();
  if (args.size() != 3 || unrestricted(args[0]) != acc || unrestricted(args[1]) != element ||
      !args[2].isInteger(64))
    return emitOpError("expects its body to take the accumulator (")
           << acc << "), the element (" << element << ") and the index (i64), not " << args;
  return ops::verifyLoopBody(*this, getBody(), args, acc);
}

std::optional<StringRef> ArrayGenerateOp::getCrashCause() { return std::nullopt; }
std::optional<StringRef> ArrayFoldOp::getCrashCause() { return std::nullopt; }

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
  ops::ioEffects(getCrashCause(), getArray(), effects);
}
void ArrayFoldOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  ops::ioEffects(getCrashCause(), Value(), effects);
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
// accumulator, and a match's yield is the match's results.
MutableOperandRange YieldOp::getMutableSuccessorOperands(RegionSuccessor) {
  if (isa<ArrayGenerateOp>((*this)->getParentOp()))
    return MutableOperandRange(*this, /*start=*/0, /*length=*/0);
  return MutableOperandRange(*this);
}
