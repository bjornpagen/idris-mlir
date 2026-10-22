// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The grades: `!idr.graded`'s hooks (its spelling, its canonical form), a
// type at a grade, what its grade says of how a value may be used and what
// it holds, and the values seen through the positions their grades put them
// in.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Quantities.h"
#include "idr/IR/Symbols.h"

#include "mlir/IR/DialectImplementation.h"
#include "llvm/ADT/SmallPtrSet.h"
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

} // namespace

// A hold, if one comes next, read word by word against the specification's
// spellings: the words said so far narrow the holds still possible, and
// each next word is one of theirs. A carrier never starts with a hold's
// first word, so the hold is told from the carrier by its first word.
ParseResult idr::parseHold(AsmParser &parser, FailureOr<std::optional<Hold>> &hold) {
  constexpr Hold holds[] = {Hold::counted(),           Hold::counted(Unique::Self),
                            Hold::counted(Unique::Deep), Hold::scoped(),
                            Hold::scoped(Unique::Self),  Hold::scoped(Unique::Deep),
                            Hold::staticData()};
  SmallVector<StringRef, 3> said;
  auto wordsOf = [](Hold h) {
    SmallVector<StringRef, 3> words;
    h.spelling().split(words, ' ');
    return words;
  };
  for (bool more = true; more;) {
    more = false;
    for (Hold candidate : holds) {
      SmallVector<StringRef, 3> words = wordsOf(candidate);
      if (words.size() <= said.size() || !llvm::equal(ArrayRef(words).take_front(said.size()), said))
        continue;
      if (succeeded(parser.parseOptionalKeyword(words[said.size()]))) {
        said.push_back(words[said.size()]);
        more = true;
        break;
      }
    }
  }
  if (said.empty()) {
    hold = std::optional<Hold>();
    return success();
  }
  for (Hold candidate : holds)
    if (llvm::equal(wordsOf(candidate), said)) {
      hold = std::optional<Hold>(candidate);
      return success();
    }
  return parser.emitError(parser.getCurrentLocation(), "expected a hold, got `")
         << llvm::join(said, " ") << "`";
}

void idr::printHold(AsmPrinter &printer, std::optional<Hold> hold) {
  if (hold)
    printer << hold->spelling();
}

// `<uses, [hold,] carrier>`: `!idr.graded<once, counted unique deep, !L>`,
// `!idr.graded<once, i64>`.
Type GradedType::parse(AsmParser &parser) {
  SMLoc loc = parser.getCurrentLocation();
  if (parser.parseLess())
    return {};
  FailureOr<Uses> uses = parseUses(parser);
  if (failed(uses) || parser.parseComma())
    return {};
  FailureOr<std::optional<Hold>> hold;
  if (failed(parseHold(parser, hold)) || failed(hold) || (*hold && parser.parseComma()))
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
  if (hold.has_value() != holdsReferences(carrier))
    return emitError() << (hold ? "expects no hold of " : "expects a hold of ") << carrier
                       << (hold ? ", which holds no reference" : ", which holds references");
  if (Grade{uses, hold} == bareGrade(carrier))
    return emitError() << "expects a grade other than " << carrier
                       << "'s bare grade, which is the carrier itself";
  return success();
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
  Grade a = gradeOf(from);
  Grade b = gradeOf(to);
  if (unrestricted(from) != unrestricted(to) || a.uses != b.uses)
    return false;
  return a.hold == b.hold || (a.hold && b.hold && a.hold->fits(*b.hold));
}

std::optional<Exclusive> idr::asExclusive(Value value) {
  if (holdOf(value.getType()) != Hold::counted(Unique::Deep))
    return std::nullopt;
  return Exclusive(value);
}

Type idr::fieldType(Type scrutinee, Type carrier, Uses uses, Recursion recursion) {
  Grade value = gradeOf(scrutinee);
  Grade read = bareGrade(carrier);
  read.uses = times(value.uses, uses);
  if (read.hold && value.hold)
    read.hold = value.hold->read(recursion);
  return graded(read, carrier);
}

bool idr::isClosureType(Type type) { return isa<FnType>(unrestricted(type)); }

bool idr::isLazyType(Type type) { return isa<LazyType>(unrestricted(type)); }

//===----------------------------------------------------------------------===//
// Values through their positions
//===----------------------------------------------------------------------===//

namespace {

// The value a cast into or out of a linear position moved: the operand of
// an op that keeps its operand's value (Idr_SameValue) at other uses.
std::optional<Value> linearPositionOf(Value value) {
  Operation *def = value.getDefiningOp();
  if (!def || !def->hasTrait<SameValue>())
    return std::nullopt;
  Value moved = def->getOperand(0);
  if (usesOf(moved.getType()) == usesOf(value.getType()))
    return std::nullopt;
  return moved;
}

} // namespace

SmallVector<Value, 4> idr::definitionChain(Value start,
                                           function_ref<std::optional<Value>(Value)> step) {
  SmallVector<Value, 4> chain{start};
  llvm::SmallPtrSet<Value, 4> passed{start};
  for (std::optional<Value> next = step(start); next && passed.insert(*next).second;
       next = step(*next))
    chain.push_back(*next);
  return chain;
}

SmallVector<Value, 4> idr::linearPositions(Value value) {
  return definitionChain(value, linearPositionOf);
}

Value idr::throughLinear(Value value) { return linearPositions(value).back(); }

// An op says it keeps its operand's value (Idr_SameValue); a field read
// takes its operand refined to one constructor, which its type names; a
// match enters each of its regions with its operands refined (the
// scrutinee first, then what it forwards), each the same value at a type
// that says more; a loan's view is the value it lends, and the owner it
// gives back is that value.
Source idr::sourceOf(Value value) {
  if (auto result = dyn_cast<OpResult>(value)) {
    Operation *op = result.getOwner();
    if (op->hasTrait<SameValue>())
      return Same{op->getOperand(0)};
    if (auto loan = dyn_cast<LendOp>(op); loan && result == loan.getReturned())
      return Same{loan.getOwner()};
    if (auto read = dyn_cast<DataFieldOp>(op))
      if (std::optional<Tag> tag = dataTypeOf(read.getValue().getType()).singleTag())
        return Field{read.getValue(), *tag, static_cast<unsigned>(read.getIndex())};
    return Made{};
  }
  auto arg = cast<BlockArgument>(value);
  Operation *parent = arg.getOwner()->getParentOp();
  if (auto loan = dyn_cast<LendOp>(parent); loan && arg == loan.getView())
    return Same{loan.getOwner()};
  if (auto match = dyn_cast<DataMatchOp>(parent); match && arg.getOwner()->isEntryBlock())
    return Same{match->getOperand(arg.getArgNumber())};
  return Made{};
}

// What counting and linearity make of an array changes which value names
// it, not which cell it is.
Value idr::arrayRoot(Value array) {
  return definitionChain(array, [](Value value) -> std::optional<Value> {
           Source source = sourceOf(value);
           if (auto *same = std::get_if<Same>(&source))
             return same->value;
           return std::nullopt;
         }).back();
}

// Each value the grade changes make of `value` is the result of a use of
// the one before, so the values form a tree rooted at `value` and each is
// met once; in an unreachable block an op may carry its own result, which
// the walk does not follow back.
bool idr::fieldReadOnce(Value value, unsigned index) {
  unsigned reads = 0;
  SmallVector<Value, 4> work{value};
  while (!work.empty()) {
    Value held = work.pop_back_val();
    for (Operation *user : held.getUsers()) {
      if (user->hasTrait<ResultCarriesOperand>()) {
        if (user->getResult(0) != held)
          work.push_back(user->getResult(0));
        continue;
      }
      auto read = dyn_cast<DataFieldOp>(user);
      if (!read)
        return false;
      if (read.getIndex() == index)
        ++reads;
    }
  }
  return reads == 1;
}

// One cast between types equal up to their uses, whose direction its types
// say.
Value idr::heldAs(OpBuilder &b, Location loc, Value value, Type type) {
  if (value.getType() == type)
    return value;
  return LinCastOp::create(b, loc, type, value);
}

//===----------------------------------------------------------------------===//
// The types a field may have
//===----------------------------------------------------------------------===//

namespace {

// An element of an array: a field type at no grade.
bool isElementType(Type element) { return !isa<GradedType>(element) && isFieldType(element); }

// A value array: a ranked tensor without an encoding, of any rank and
// extents. After bufferization, its buffer: a memref in the default memory
// space, in the identity layout, of any rank and extents. Its element is
// no shaped value: an array of arrays is one array of a higher rank.
bool isValueArray(Type type) {
  auto shaped = dyn_cast<ShapedType>(type);
  if (!shaped || isa<ShapedType>(shaped.getElementType()) ||
      !isElementType(shaped.getElementType()))
    return false;
  if (auto tensor = dyn_cast<RankedTensorType>(type))
    return !tensor.getEncoding();
  auto memref = dyn_cast<MemRefType>(type);
  return memref && !memref.getMemorySpace() && memref.getLayout().isIdentity();
}

} // namespace

// A runtime value of ours is an element type of memref, which its ODS says
// beside it, and so a field's type; the dialect's other types (a grade, a
// token, a destination, a cell, a lifetime) are no values a cell holds.
bool idr::isFieldType(Type type) {
  type = unrestricted(type);
  if (auto integer = dyn_cast<IntegerType>(type))
    return integer.isSignless() && llvm::is_contained({8u, 16u, 32u, 64u}, integer.getWidth());
  if (isa<IdrDialect>(type.getDialect()))
    return isa<MemRefElementTypeInterface>(type);
  return isa<Float64Type>(type) || isArray(type) || isValueArray(type);
}

// An array of mutable memory: at most one dimension, each dynamic, in the
// identity layout, in mutable memory, the shapes the runtime's array cell
// has (a length, then the elements in order), an IORef being the cell of
// one element, whose length is 1 and no value carries. The memory space
// tells it from a value buffer of the same element, which a cell may hold
// after it is shared and so cannot be written.
bool idr::isArray(Type type) {
  auto memref = dyn_cast<MemRefType>(type);
  if (!memref || memref.getRank() > 1 || !llvm::all_of(memref.getShape(), ShapedType::isDynamic) ||
      !memref.getLayout().isIdentity() ||
      !isa_and_nonnull<MutableSpaceAttr>(memref.getMemorySpace()))
    return false;
  return isElementType(memref.getElementType());
}

bool idr::isRank1Array(Type type) {
  return isArray(type) && cast<MemRefType>(type).getRank() == 1;
}
