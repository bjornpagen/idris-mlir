// The string ops: the builders that walk a list, the rules and ranges of
// the others, when an index or a head may run before its guard, and the
// output and head canonicalizations. What a list op's own types say is its
// verify(); what its declaration says is a symbol use, checked once per
// module verify.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Canon.h"
#include "idr/IR/Ranges.h"
#include "idr/IR/Symbols.h"

#include "mlir/IR/PatternMatch.h"

#include <cstdint>

using namespace mlir;
using namespace idr;

namespace {

// A list the builders walk is a box: its declaration then says the rest.
LogicalResult verifyListBox(Operation *op, Value list) {
  if (!isa<BoxType>(unrestricted(list.getType())))
    return op->emitOpError("walks a list, a box of a nil and a cons, not ") << list.getType();
  return success();
}

// What a list holds: the first field of its declaration's constructor of
// two fields, the cons; null when it has none.
Type elementOf(DataOp data) {
  for (CtorOp ctor : data.getBody().front().getOps<CtorOp>())
    if (ctor.getFieldTypes().size() == 2)
      return ctor.getFieldType(0);
  return {};
}

} // namespace

LogicalResult StrPackOp::verify() { return verifyListBox(*this, getList()); }

LogicalResult StrPackOp::verifySymbolUses(SymbolTableCollection &symbols) {
  Type list = getList().getType();
  return listCons(*this, lookupData(symbols, *this, list), list, IntegerType::get(getContext(), 32))
             ? success()
             : failure();
}

LogicalResult StrConcatOp::verify() { return verifyListBox(*this, getList()); }

LogicalResult StrConcatOp::verifySymbolUses(SymbolTableCollection &symbols) {
  Type list = getList().getType();
  return listCons(*this, lookupData(symbols, *this, list), list, StrType::get(getContext()))
             ? success()
             : failure();
}

// With no table in hand: one scan of the module's top level.
Type PutListOp::getElementType() {
  DataOp data = declarationOf(*this, getList().getType());
  return data ? elementOf(data) : Type();
}

LogicalResult PutListOp::verify() { return verifyListBox(*this, getList()); }

// A list pack or concat walks.
LogicalResult PutListOp::verifySymbolUses(SymbolTableCollection &symbols) {
  Type list = getList().getType();
  DataOp data = lookupData(symbols, *this, list);
  Type element = data ? elementOf(data) : Type();
  if (!isa_and_nonnull<StrType>(element) && element != IntegerType::get(getContext(), 32))
    return emitOpError("writes a list of characters or of strings, not ") << list;
  return listCons(*this, data, list, element) ? success() : failure();
}

LogicalResult StrShowOp::verify() {
  if (isa<FloatType>(getValue().getType()) && getIsSigned())
    return emitOpError("shows a Double, which has no signedness");
  return success();
}

void StrLengthOp::inferResultRanges(ArrayRef<ConstantIntRanges>, SetIntRangeFn setResultRange) {
  setResultRange(getResult(), idr::ranges::nonNegative(64, 0, INT64_MAX));
}

// A scalar value, or 0 at the end.
void StrScalarAtOp::inferResultRanges(ArrayRef<ConstantIntRanges>, SetIntRangeFn setResultRange) {
  setResultRange(getResult(), idr::ranges::nonNegative(32, 0, 0x10FFFF));
}

// An offset within the string's bytes.
void StrScalarEndOp::inferResultRanges(ArrayRef<ConstantIntRanges>, SetIntRangeFn setResultRange) {
  setResultRange(getResult(), idr::ranges::nonNegative(64, 0, INT64_MAX));
}

// An index past the string's end reads outside it, so it stays below its
// guard against this string's length, or below the path that proved the
// guard away.
Speculation::Speculatability StrIndexOp::getSpeculatability() {
  return checkSpeculatability(*this, getIndexMutable().getOperandNumber());
}

Speculation::Speculatability StrHeadOp::getSpeculatability() {
  return checkSpeculatability(*this, getStrMutable().getOperandNumber());
}

// Output and the first character of a string being built are taken apart
// into the pieces it is built of; output of a list takes one step of the
// list it meets.
void PutStrOp::getCanonicalizationPatterns(RewritePatternSet &results, MLIRContext *context) {
  canon::addPutStrPatterns(results, context);
}

void PutListOp::getCanonicalizationPatterns(RewritePatternSet &results, MLIRContext *context) {
  canon::addPutListPatterns(results, context);
}

void StrHeadOp::getCanonicalizationPatterns(RewritePatternSet &results, MLIRContext *context) {
  canon::addStrHeadPatterns(results, context);
}

// Whether output writes a string in the pieces it is built of, where the
// output patterns take it apart.
bool idr::writtenInPieces(Value str) {
  Operation *builder = str.getDefiningOp();
  if (isa_and_nonnull<StrAppendOp, StrConsOp, StrFromCharOp, StrShowOp>(builder))
    return true;
  return isa_and_nonnull<StrPackOp, StrConcatOp>(builder) && str.hasOneUse();
}
