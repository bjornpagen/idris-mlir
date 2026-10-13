// The ops on arrays: new, get, set, and the loops generate and fold, with
// their rules, their syntax, their shapes and their effects. How control
// enters and leaves a loop's body is the region ops' unit's.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Canon.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/Matchers.h"
#include "mlir/IR/OpImplementation.h"
#include "mlir/IR/PatternMatch.h"

using namespace mlir;
using namespace idr;

namespace {

// An access takes one index per dimension of its array, and a new array one
// size: what memref.load and memref.alloc ask of theirs.
LogicalResult verifyCount(Operation *op, size_t count, StringRef what, MemRefType array) {
  if (count != static_cast<size_t>(array.getRank()))
    return op->emitOpError("takes ") << count << " " << what << " for an array of rank "
                                     << array.getRank();
  return success();
}

// An element moves into an array, or out of it, at the element type at any
// grade: plain before idr-rc, and owned after it when it holds references.
LogicalResult verifyElement(Operation *op, StringRef what, Type type, MemRefType array) {
  if (view(type) != array.getElementType())
    return op->emitOpError() << what << " has type " << type << ", but the array holds "
                             << array.getElementType();
  return success();
}

// An element a vector lane computes: an integer or a float.
LogicalResult verifyWord(Operation *op, StringRef what, Type type) {
  if (!isa<IntegerType, FloatType>(type))
    return op->emitOpError() << what << " is " << type
                             << ", and a loop over an array computes machine words: integers "
                                "and floats";
  return success();
}

// The body of a loop over an array ends in idr.yield, or in ub.unreachable
// after a crash.
LogicalResult verifyLoopEnd(Operation *op, Region &body) {
  if (isa<YieldOp, ub::UnreachableOp>(body.front().getTerminator()))
    return success();
  return op->emitOpError("expects its body to end in idr.yield or ub.unreachable");
}

// `(%x: T, ...)` and the region they are the arguments of.
ParseResult parseLoopBody(OpAsmParser &parser, OperationState &result) {
  SmallVector<OpAsmParser::Argument> args;
  if (parser.parseArgumentList(args, OpAsmParser::Delimiter::Paren, /*allowType=*/true))
    return failure();
  return parser.parseRegion(*result.addRegion(), args);
}

void printLoopBody(OpAsmPrinter &printer, Region &body) {
  printer << " (";
  llvm::interleaveComma(body.getArguments(), printer,
                        [&](BlockArgument arg) { printer.printRegionArgument(arg); });
  printer << ") ";
  printer.printRegion(body, /*printEntryBlockArgs=*/false);
}

// An index as its access's guard was given it: the guard's result is the
// value it checked.
Value unguarded(Value index) {
  if (auto guard = index.getDefiningOp<CheckInBoundsOp>())
    return guard.getIndex();
  return index;
}

// Whether two indices are one: the same value once seen through their
// guards, or two constants of the same value, which a pass that puts a
// constant in place of a value it knows makes once per use.
bool sameIndex(Value x, Value y) {
  x = unguarded(x);
  y = unguarded(y);
  if (x == y)
    return true;
  APInt a, b;
  return matchPattern(x, m_ConstantInt(&a)) && matchPattern(y, m_ConstantInt(&b)) &&
         a.getBitWidth() == b.getBitWidth() && a == b;
}

} // namespace

bool idr::sameElement(Value array, ValueRange indices, Value otherArray, ValueRange otherIndices) {
  return arrayRoot(array) == arrayRoot(otherArray) &&
         llvm::equal(indices, otherIndices, sameIndex);
}

LogicalResult ArrayNewOp::verify() {
  if (failed(verifyCount(*this, getSizes().size(), "sizes", getArrayType())))
    return failure();
  return verifyElement(*this, "the fill", getFill().getType(), getArrayType());
}

// A read that moves its element out leaves the element's place empty, so
// the next IO on its world, its world's one use, is the write that fills
// that place again, in its block: anything else between would see the
// empty place. A machine word is never counted and is read as a memref's
// element, which a loop may take over, so it does not move. Whether an
// element of any other type holds a reference may change as passes run
// (defunctionalization makes a closure a sum, of captured words only, say),
// so it is MoveOutBeforeSet's to ask, and a read that moves an element
// holding none only empties nothing.
LogicalResult ArrayGetOp::verify() {
  if (failed(verifyCount(*this, getIndices().size(), "indices", getArrayType())))
    return failure();
  if (getMoves()) {
    if (getArrayType().getElementType().isIntOrIndexOrFloat())
      return emitOpError("moves out a machine word, which holds no reference");
    auto set = getNext().hasOneUse() ? dyn_cast<ArraySetOp>(*getNext().getUsers().begin())
                                     : ArraySetOp();
    if (!set || set->getBlock() != (*this)->getBlock() ||
        !sameElement(getArray(), getIndices(), set.getArray(), set.getIndices()))
      return emitOpError("moves its element out, but its world does not go next to a write of "
                         "that element in its block");
  }
  return verifyElement(*this, "the result", getValue().getType(), getArrayType());
}

LogicalResult ArraySetOp::verify() {
  if (failed(verifyCount(*this, getIndices().size(), "indices", getArrayType())))
    return failure();
  return verifyElement(*this, "the value", getValue().getType(), getArrayType());
}

// The read before a write of the same element moves the element out.
void ArraySetOp::getCanonicalizationPatterns(RewritePatternSet &results, MLIRContext *context) {
  canon::addMoveOutPatterns(results, context);
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
  ioEffects(getArray(), effects);
}
void ArrayGetOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  ioEffects(Value(), effects);
}
void ArraySetOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  ioEffects(Value(), effects);
}

// `idr.array.generate %n, %fill, %w : E -> memref<?xE> (%i: i64) {...}`
ParseResult ArrayGenerateOp::parse(OpAsmParser &parser, OperationState &result) {
  OpAsmParser::UnresolvedOperand size, fill, worldOperand;
  Type fillType, arrayType;
  if (parser.parseOperand(size) || parser.parseComma() || parser.parseOperand(fill) ||
      parser.parseComma() || parser.parseOperand(worldOperand) ||
      parser.parseOptionalAttrDict(result.attributes) || parser.parseColon() ||
      parser.parseType(fillType) || parser.parseArrow() || parser.parseType(arrayType) ||
      parseLoopBody(parser, result))
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
  printLoopBody(printer, getBody());
}

// The body takes the index, an i64.
LogicalResult ArrayGenerateOp::verify() {
  Type element = getArrayType().getElementType();
  if (failed(verifyWord(*this, "the element", element)) ||
      failed(verifyElement(*this, "the fill", getFill().getType(), getArrayType())))
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
  if (failed(verifyLoopEnd(*this, getBody())))
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
      parser.parseArrow() || parser.parseType(resultType) || parseLoopBody(parser, result))
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
  printLoopBody(printer, getBody());
}

LogicalResult ArrayFoldOp::verify() {
  Type element = getArrayType().getElementType();
  Type acc = unrestricted(getInit().getType());
  if (failed(verifyWord(*this, "the element", element)) ||
      failed(verifyWord(*this, "the accumulator", acc)))
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
LogicalResult ArrayFoldOp::verifyRegions() { return verifyLoopEnd(*this, getBody()); }

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
  ioEffects(getArray(), effects);
}
void ArrayFoldOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  ioEffects(Value(), effects);
}
