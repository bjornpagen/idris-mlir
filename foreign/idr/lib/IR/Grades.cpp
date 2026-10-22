// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The grades: `!idr.graded`'s hooks (its spelling, its canonical form, what
// a value of it holds), a type at a grade, what its grade says of how a
// value may be used and what it holds, and the types a field may have. The
// grade's one op, the cast, is Lifetimes/Cast.cpp's, as an op that states
// the lifetime of a scoped value it makes.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"
#include "idr/Support/Enum.h"

#include "mlir/IR/DialectImplementation.h"
#include "llvm/ADT/StringExtras.h"

#include <optional>

using namespace mlir;
using namespace idr;

//===----------------------------------------------------------------------===//
// !idr.graded
//===----------------------------------------------------------------------===//

namespace {

// `once` or `many`, as the specification spells them.
FailureOr<Uses> parseUses(AsmParser &parser) {
  SMLoc loc = parser.getCurrentLocation();
  StringRef keyword;
  if (parser.parseKeyword(&keyword))
    return failure();
  if (std::optional<Uses> uses = symbolizeUses(keyword))
    return *uses;
  return parser.emitError(loc, "expected how often a value is used, got `") << keyword << "`";
}

// A hold's words, as the type prints it.
SmallVector<StringRef, 3> wordsOf(HoldCase kase) {
  SmallVector<StringRef, 3> words;
  Hold::fromCase(kase).spelling().split(words, ' ');
  return words;
}

// The next word of a hold whose spelling begins with `said`, if the next
// keyword is one.
std::optional<StringRef> parseNextWord(AsmParser &parser, ArrayRef<StringRef> said) {
  for (HoldCase kase : allOf<HoldCase>()) {
    SmallVector<StringRef, 3> words = wordsOf(kase);
    if (words.size() > said.size() && llvm::equal(ArrayRef(words).take_front(said.size()), said) &&
        succeeded(parser.parseOptionalKeyword(words[said.size()])))
      return words[said.size()];
  }
  return std::nullopt;
}

// A hold, if one comes next, read word by word against the specification's
// spellings: the words said so far narrow the holds still possible, and
// each next word is one of theirs. A carrier never starts with a hold's
// first word, so the hold is told from the carrier by its first word.
FailureOr<std::optional<Hold>> parseHold(AsmParser &parser) {
  SmallVector<StringRef, 3> said;
  while (std::optional<StringRef> next = parseNextWord(parser, said))
    said.push_back(*next);
  if (said.empty())
    return std::optional<Hold>();
  for (HoldCase kase : allOf<HoldCase>())
    if (llvm::equal(wordsOf(kase), said))
      return std::optional<Hold>(Hold::fromCase(kase));
  return parser.emitError(parser.getCurrentLocation(), "expected a hold, got `")
         << llvm::join(said, " ") << "`";
}

} // namespace

// `<uses, [hold,] carrier>`: `!idr.graded<once, counted unique deep, !L>`,
// `!idr.graded<once, i64>`.
Type GradedType::parse(AsmParser &parser) {
  SMLoc loc = parser.getCurrentLocation();
  if (parser.parseLess())
    return {};
  FailureOr<Uses> uses = parseUses(parser);
  if (failed(uses) || parser.parseComma())
    return {};
  FailureOr<std::optional<Hold>> hold = parseHold(parser);
  if (failed(hold) || (*hold && parser.parseComma()))
    return {};
  Type carrier;
  if (parser.parseType(carrier) || parser.parseGreater())
    return {};
  return getChecked([&] { return parser.emitError(loc); }, parser.getContext(), *uses, *hold,
                    carrier);
}

void GradedType::print(AsmPrinter &printer) const {
  printer << '<' << stringifyUses(getUses()) << ", ";
  if (std::optional<Hold> hold = getHold())
    printer << hold->spelling() << ", ";
  printer.printType(getCarrier());
  printer << '>';
}

// The canonical form, the one rule a type parameter cannot carry: a grade
// is of a carrier, never of a grade; a type used once by its type takes
// none, and neither does a lifetime, which is never consumed; a hold
// exactly on a carrier that holds references, which the carrier says; and
// never the carrier's bare grade, which is the carrier.
LogicalResult GradedType::verify(function_ref<InFlightDiagnostic()> emitError, Uses uses,
                                 std::optional<Hold> hold, Type carrier) {
  if (isa<GradedType>(carrier))
    return emitError() << "expects a grade of a carrier, got one of " << carrier;
  if (idr::isLinearByType(carrier) || isa<LifetimeType>(carrier))
    return emitError() << "expects no grade of " << carrier
                       << ", which is used exactly once by its type or is a lifetime";
  if (hold.has_value() != idr::holdsReferences(carrier))
    return emitError() << (hold ? "expects no hold of " : "expects a hold of ") << carrier
                       << (hold ? ", which holds no reference" : ", which holds references");
  if (Grade{uses, hold} == bareGrade(carrier))
    return emitError() << "expects a grade other than " << carrier
                       << "'s bare grade, which is the carrier itself";
  return success();
}

// What a value at a grade holds is its carrier's; the verifier refuses a
// grade of a carrier used once by its type, so no graded type is one.
bool GradedType::holdsReferences() const { return idr::holdsReferences(getCarrier()); }
bool GradedType::isLinearByType() const { return false; }
bool GradedType::isCounted() const { return idr::isCounted(getCarrier()); }
bool GradedType::isCellPointer() const { return idr::isCellPointer(getCarrier()); }

// A value at a grade is its carrier's value, so it prints with the name its
// carrier gives one; a carrier that names none leaves it upstream's number.
void GradedType::getAsmName(OpAsmSetNameFn setNameFn) const {
  if (auto named = dyn_cast<OpAsmTypeInterface>(getCarrier()))
    named.getAsmName(setNameFn);
}

//===----------------------------------------------------------------------===//
// A type at a grade
//===----------------------------------------------------------------------===//

Grade idr::bareGrade(Type carrier) {
  if (holdsReferences(carrier))
    return {Uses::Many, Hold::counted()};
  return {Uses::Many, std::nullopt};
}

Grade idr::gradeOf(Type type) {
  if (auto graded = dyn_cast<GradedType>(type))
    return {graded.getUses(), graded.getHold()};
  if (idr::isLinearByType(type))
    return {Uses::Once, std::nullopt};
  return bareGrade(type);
}

Type idr::graded(Grade grade, Type carrier) {
  carrier = unrestricted(carrier);
  if (idr::isLinearByType(carrier) || grade == bareGrade(carrier))
    return carrier;
  return GradedType::get(carrier.getContext(), grade.uses, grade.hold, carrier);
}

Type idr::unrestricted(Type type) {
  auto graded = dyn_cast<GradedType>(type);
  return graded ? graded.getCarrier() : type;
}

Uses idr::usesOf(Type type) { return gradeOf(type).uses; }

std::optional<Hold> idr::holdOf(Type type) { return gradeOf(type).hold; }

Type idr::atUses(Type type, Uses uses) {
  Grade grade = gradeOf(type);
  grade.uses = uses;
  return graded(grade, type);
}

Type idr::atHold(Type type, Hold hold) {
  Grade grade = gradeOf(type);
  if (!grade.hold)
    return type;
  grade.hold = hold;
  return graded(grade, type);
}

bool idr::freedBy(Type type, Release release) {
  std::optional<Hold> hold = holdOf(type);
  return hold && hold->release() == release;
}

bool idr::claims(Type type, Unique unique) {
  std::optional<Hold> hold = holdOf(type);
  return hold && hold->claims(unique);
}

Type idr::shared(Type type) {
  std::optional<Hold> hold = holdOf(type);
  return hold ? atHold(type, hold->refined(Unique::None)) : type;
}

bool idr::forgets(Type from, Type to) {
  return unrestricted(from) == unrestricted(to) && usesOf(from) == usesOf(to) &&
         holdFits(from, to);
}

bool idr::holdFits(Type from, Type to) {
  std::optional<Hold> held = holdOf(from);
  std::optional<Hold> asked = holdOf(to);
  return held == asked || (held && asked && held->fits(*asked));
}

// The declaration says it: a field of a member of the family's own group,
// an application of a family whose data member promises in place, or a
// buffer, whose storage the claim on the cell holding it covers and whose
// elements it does not. A buffer is a memref field, of mutable memory or a
// value array's after bufferization, and this is the one test of whether a
// field holds one: every reader asks the reach.
FieldReach idr::fieldReach(Type declared) {
  Type field = unrestricted(declared);
  if (isa<SelfType>(field))
    return FieldReach::OwnFamily;
  if (auto data = dyn_cast<DataType>(field); data && data.promise() == Promise::InPlace)
    return FieldReach::InPlaceFamily;
  if (isa<MemRefType>(field))
    return FieldReach::HeldBuffer;
  return FieldReach::Other;
}

Type idr::fieldType(Type scrutinee, Type carrier, Uses uses, FieldReach reach) {
  Grade value = gradeOf(scrutinee);
  Grade read = bareGrade(carrier);
  read.uses = times(value.uses, uses);
  if (read.hold && value.hold)
    read.hold = value.hold->read(reach, read.uses);
  return graded(read, carrier);
}

bool idr::isClosureType(Type type) { return isa<FnType>(unrestricted(type)); }

bool idr::isLazyType(Type type) { return isa<LazyType>(unrestricted(type)); }

//===----------------------------------------------------------------------===//
// The types a field may have
//===----------------------------------------------------------------------===//

namespace {

// The element of an array of mutable memory, none for any other type: at
// most one dimension, each dynamic, in the identity layout, in mutable
// memory, the shapes the runtime's array cell has (a length, then the
// elements in order), an IORef being the cell of one element, whose length
// is 1 and no value carries. The memory space tells it from a value buffer
// of the same element, which a cell may hold after it is shared and so
// cannot be written.
Type mutableElement(Type type) {
  auto memref = dyn_cast<MemRefType>(type);
  if (!memref || memref.getRank() > 1 || !llvm::all_of(memref.getShape(), ShapedType::isDynamic) ||
      !memref.getLayout().isIdentity() ||
      !isa_and_nonnull<MutableAttr>(memref.getMemorySpace()))
    return nullptr;
  return memref.getElementType();
}

// The element of a value array, none for any other type: a ranked tensor
// without an encoding, of any rank and extents; after bufferization, its
// buffer, a memref in the default memory space, in the identity layout, of
// any rank and extents. Its element is no shaped value: an array of arrays
// is one array of a higher rank.
Type valueElement(Type type) {
  auto shaped = dyn_cast<ShapedType>(type);
  if (!shaped || isa<ShapedType>(shaped.getElementType()))
    return nullptr;
  if (auto tensor = dyn_cast<RankedTensorType>(type))
    return tensor.getEncoding() ? nullptr : shaped.getElementType();
  auto memref = dyn_cast<MemRefType>(type);
  return memref && !memref.getMemorySpace() && memref.getLayout().isIdentity()
             ? shaped.getElementType()
             : nullptr;
}

} // namespace

// A runtime value of ours is an element type of memref, which its ODS says
// beside it, and so a field's type; the dialect's other types (a grade, a
// token, a destination, a cell, a lifetime) are no values a cell holds. An
// array's element is a field type at no grade, and an array of mutable
// memory may hold arrays, so the elements are taken one array at a time,
// never by recursion on how deeply arrays nest.
bool idr::isFieldType(Type type) {
  for (type = unrestricted(type);;) {
    if (auto integer = dyn_cast<IntegerType>(type))
      return integer.isSignless() && llvm::is_contained({8u, 16u, 32u, 64u}, integer.getWidth());
    if (isa<IdrDialect>(type.getDialect()))
      return isa<MemRefElementTypeInterface>(type);
    if (isa<Float64Type>(type))
      return true;
    Type element = mutableElement(type);
    if (!element)
      element = valueElement(type);
    if (!element || isa<GradedType>(element))
      return false;
    type = element;
  }
}

bool idr::isArray(Type type) {
  Type element = mutableElement(type);
  return element && !isa<GradedType>(element) && isFieldType(element);
}

bool idr::isRank1Array(Type type) {
  return isArray(type) && cast<MemRefType>(type).getRank() == 1;
}
