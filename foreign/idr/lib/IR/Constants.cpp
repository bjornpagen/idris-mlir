// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr.constant: the dialect's values, which hold no type, and the check of a
// constant through its fields: a constructor against its data type's body,
// once per module verify through the collection the symbol-use walk hands
// over. Each constant answers for itself, through ConstantAttrInterface: at
// which types idr.constant holds it, how it is laid out as static data,
// what it names and holds, and what a fold reads of it.
// Ours answer by their classes; upstream's strings, integers and floats,
// which a constant's fields and static data hold, answer as the external
// models defined here, the one place they are named.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Families/Families.h"
#include "idr/IR/Fold.h"
#include "idr/IR/FoldParts.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Symbols.h"
#include "idr/Support/Footprint.h"

#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/BuiltinTypes.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/Support/ErrorHandling.h"
#include "llvm/Support/raw_ostream.h"

#include <cassert>
#include <optional>
#include <string>

using namespace mlir;
using namespace idr;

//===----------------------------------------------------------------------===//
// At which types idr.constant holds a constant of ours
//===----------------------------------------------------------------------===//

namespace {

// A constructor of `data` is held at a type whose data type `data` refines,
// by the one rule a field is filled by (fillsField): its own, or one that
// leaves more constructors possible, as a list's Nil is held in a field of
// the list. Its static data is laid out at that type (getStaticForm).
bool holdsConstructor(DataType data, Type type) {
  DataType place = dataTypeOf(type);
  return place && families::refines(data, place);
}

// A literal of a type that says it is one of its literals: a big, and a
// string.
bool literalOf(Attribute value, Type type) {
  auto literal = dyn_cast<LiteralTypeInterface>(unrestricted(type));
  return literal && literal.isLiteral(value);
}

} // namespace

bool ConAttr::isBuildableAt(Type type) const { return holdsConstructor(getData(), type); }

// A constructor is static data, in a cell.
bool idr::fold::constructorStandsAt(const DataType &data, Type type) {
  return holdsConstructor(data, type) && constantStandsAt(type, Storage::Cell);
}

// A big is a literal of the types that say a big is one of theirs: an
// Integer's, and a natural's where it is never negative.
bool BigAttr::isBuildableAt(Type type) const { return literalOf(*this, type); }

//===----------------------------------------------------------------------===//
// What a constant of ours names and holds
//===----------------------------------------------------------------------===//

// The constructor's cells hold fields of its data type, each handed to
// `part` at the type the product rule gives it (fieldType), as a match
// binds it: used as often as the cell holding it times the field's own
// uses, holding what the cell holds as far as the cell's claim reaches into
// it. So a constant fills a linear field as its plain value, and a field of
// static data is static data. Its data type refines the type it is held
// at, which isBuildableAt has said, and its fields are its own data
// type's, the place giving them only their grade. A constructor is checked
// a cell at a time, each field at its type in its own cell's application,
// however long its run, and never through the suffix that reading the
// field along its spine would build. Each cell after the first is the
// field along the spine of the one before, held as that field is, so its
// application is that field's type there, refined to the same constructor:
// a run of a vector's cells is checked at each cell's own index. One cell
// has no field after it.
LogicalResult ConAttr::verifyParts(Operation *holder, SymbolTableCollection &, Type type,
                                   function_ref<void(Attribute, Type)> part) const {
  Tag tag = getTag();
  auto spine = static_cast<unsigned>(getSpine());
  DataType at = getData();
  StringRef label = at.ctor(tag).label;
  Type held = type;
  for (unsigned cell = 0, cells = getRunLength(); cell < cells; ++cell) {
    std::optional<SmallVector<Type>> fields = at.determinedFields(tag);
    if (!fields)
      return holder->emitOpError("has a cell of @")
             << label << " at " << at << ", where its binders are not determined";
    ArrayRef<Type> declared = at.ctor(tag).fields;
    auto partAt = [&](unsigned index) {
      Type field = (*fields)[index];
      return fieldType(held, unrestricted(field), usesOf(field), fieldReach(declared[index]));
    };
    for (auto [position, field] : llvm::enumerate(getCell(cell)))
      part(field, partAt(fieldOfCell(cell, static_cast<unsigned>(position))));
    if (cell + 1 == cells)
      break;
    Type along = partAt(spine);
    DataType next = dataTypeOf(along);
    if (!next || next.getGroup() != at.getGroup() || next.getMember() != at.getMember())
      return holder->emitOpError("has a run of @")
             << label << " along field " << spine << ", which holds no @" << label;
    at = next.refined({tag});
    held = along;
  }
  return success();
}

// A big holds nothing more to check.
LogicalResult BigAttr::verifyParts(Operation *, SymbolTableCollection &, Type,
                                   function_ref<void(Attribute, Type)>) const {
  return success();
}

//===----------------------------------------------------------------------===//
// How a constant is laid out as static data
//===----------------------------------------------------------------------===//

// A constructor at the type of the place that holds it (a constant op's
// result, or a field's slot). One whose own type lays out apart from its
// place's, a closed one held in place where the place holds its member at
// an unknown index, is the same constructor at the place's type, so its
// datum and its words are the place's; a numeral is its value at any
// width, so it stays as it is, and its place says the width.
StaticForm ConAttr::getStaticForm(Type held) const {
  ConAttr con = *this;
  DataType place = dataTypeOf(held);
  if (place && !families::isNumber(place.layout()) &&
      families::layoutMatch(getData(), place) != LayoutMatch::SameLayout)
    con = ConAttr::get(getContext(), place.refinedTo(getTag(), {}), getFields());
  Layout layout = con.getData().layout();
  if (families::isNumber(layout)) {
    assert(place && "a numeral is held at a data type");
    return static_form::Numeral{{place}, families::numeralValue(con)};
  }
  if (layout == Layout::InPlace)
    return static_form::InPlace{{con}};
  // The constructor's verifier refuses a frame stack's family, so what is
  // left is a cell.
  assert(layout == Layout::Cell && "a constant constructor is a number, in place or in a cell");
  return static_form::Cell{{con}};
}

StaticForm BigAttr::getStaticForm(Type) const { return static_form::Big{{*this}}; }

// Every constant answers for itself. Essential, the one attribute static
// data holds that is no constant: poison, ub's, which the lowering makes for
// a value no path reads.
StaticForm idr::staticFormOf(Attribute value, Type held) {
  if (auto constant = dyn_cast<ConstantAttrInterface>(value))
    return constant.getStaticForm(held);
  if (isa<ub::PoisonAttr>(value))
    return static_form::Nothing{};
  std::string written;
  llvm::raw_string_ostream stream(written);
  stream << value;
  llvm::reportFatalInternalError(llvm::Twine("static data of ") + written +
                                 ", which is no constant");
}

//===----------------------------------------------------------------------===//
// What a fold reads of a constant of ours
//===----------------------------------------------------------------------===//

// A big's integer; a constructor whole.
FoldValue BigAttr::getFoldValue() const { return fold_value::Big{{*this}}; }
FoldValue ConAttr::getFoldValue() const { return fold_value::Constructor{{*this}}; }

//===----------------------------------------------------------------------===//
// Upstream's constants
//===----------------------------------------------------------------------===//

namespace {

// What every upstream constant answers alike: it names nothing, so it has no
// part to check.
template <class Model, class A>
struct UpstreamConstant : ConstantAttrInterface::ExternalModel<Model, A> {
  LogicalResult verifyParts(Attribute, Operation *, SymbolTableCollection &, Type,
                            function_ref<void(Attribute, Type)>) const {
    return success();
  }
};

// A string is the literal of the type that says it is one of its literals,
// a string's; it is laid out at its own datum, and a fold reads its text.
struct StringConstant : UpstreamConstant<StringConstant, StringAttr> {
  bool isBuildableAt(Attribute value, Type type) const { return literalOf(value, type); }
  StaticForm getStaticForm(Attribute value, Type) const {
    return static_form::Text{cast<StringAttr>(value)};
  }
  FoldValue getFoldValue(Attribute value) const {
    return fold_value::Text{cast<StringAttr>(value)};
  }
};

// An integer and a Double are literals of their types too, but idr.constant
// holds neither: their constant is arith's, which every fold and pattern of
// arith reads, one constant op per value. A field holds one as a word of
// exactly its type (fold::buildable), and static data lays it out as that
// word.
template <class Model, class A>
struct WordConstant : UpstreamConstant<Model, A> {
  bool isBuildableAt(Attribute, Type) const { return false; }
  StaticForm getStaticForm(Attribute value, Type) const {
    return static_form::Word{cast<A>(value)};
  }
};

struct IntegerConstant : WordConstant<IntegerConstant, IntegerAttr> {
  FoldValue getFoldValue(Attribute value) const {
    return fold_value::Integer{cast<IntegerAttr>(value).getValue()};
  }
};

// Essential, a float's width is its value's, which its class leaves open:
// a fold reads a Double as the runtime's operands are read (fold::realOf),
// and a float of another width not at all.
struct FloatConstant : WordConstant<FloatConstant, FloatAttr> {
  FoldValue getFoldValue(Attribute value) const {
    if (std::optional<double> real = fold::realOf(value))
      return fold_value::Real{*real};
    return fold_value::Unread{};
  }
};

} // namespace

void idr::detail::addUpstreamConstants(IdrDialect &dialect) {
  MLIRContext &context = *dialect.getContext();
  StringAttr::attachInterface<StringConstant>(context);
  IntegerAttr::attachInterface<IntegerConstant>(context);
  FloatAttr::attachInterface<FloatConstant>(context);
}

//===----------------------------------------------------------------------===//
// idr.constant
//===----------------------------------------------------------------------===//

namespace {

// A part of a constant, a field, and the type it is checked at.
using Part = std::pair<Attribute, Type>;

// The parts still to check. A constant is as deep as the program's text
// makes it, so its parts wait here rather than on the stack.
using Parts = footprint::Vector<Part>;

// The parts already checked: a constant shares its parts, and each is
// checked once. Its keys are uniqued attributes and types, the parts'
// content, never a node of the IR.
using Checked = footprint::DenseMap<Part, llvm::detail::DenseSetEmpty, llvm::DenseMapInfo<Part>,
                                    llvm::detail::DenseSetPair<Part>>;

// That `op` holds a constant of its type, through every field. The
// constant stands at the op's type, which the op's verifier has judged;
// each part stands at the type its holder hands it, by the product rule,
// and is one the leaf rule of a constant's fields accepts (fold::buildable),
// which the folder of constructors asks too of the values it takes, so it
// is a constant, which then checks what it names and hands over its parts:
// a string, an integer or a Double names none.
LogicalResult verifyConstant(ConstantOp op, SymbolTableCollection &symbols) {
  Parts parts;
  Checked checked;
  auto held = [&](Attribute value, Type type) { parts.push_back({value, type}); };
  auto constant = cast<ConstantAttrInterface>(op.getValue());
  if (failed(constant.verifyParts(op, symbols, op.getType(), held)))
    return failure();
  while (!parts.empty()) {
    Part part = parts.back();
    parts.pop_back();
    if (!checked.try_emplace(part).second)
      continue;
    if (!fold::buildable(part.first, part.second))
      return op.emitOpError("has a constant ")
             << part.first << " where " << part.second << " is expected";
    if (failed(cast<ConstantAttrInterface>(part.first).verifyParts(op, symbols, part.second, held)))
      return failure();
  }
  return success();
}

} // namespace

// A field of a constant holds a word or a Double of exactly its type, or a
// value idr.constant holds at it. An array is neither: a dense tensor is a
// value of its own, which arith.constant builds and no constant constructor
// holds, so a constructor around one stays an op.
bool idr::fold::buildable(Attribute value, Type type) {
  if (isa<IntegerAttr, FloatAttr>(value))
    return cast<TypedAttr>(value).getType() == type && isFieldType(type);
  return ConstantOp::isBuildableWith(value, type);
}

Attribute idr::fold::held(Attribute constant, Type type) {
  return constant && ConstantOp::isBuildableWith(constant, type) ? constant : Attribute();
}

namespace {

// Where a constant lives at run time: a big the runtime holds in its word,
// a small, has no cell, so nothing a count could write; any other is
// static data.
fold::Storage storageOf(Attribute value) {
  auto big = dyn_cast<BigAttr>(value);
  if (!big)
    return fold::Storage::Cell;
  std::optional<int64_t> v = big.getValue().trySExtValue();
  return v && *v >= IDRIS_RT_SMALL_MIN && *v <= IDRIS_RT_SMALL_MAX ? fold::Storage::Word
                                                                    : fold::Storage::Cell;
}

} // namespace

// The kinds of value idr.constant holds, as each constant answers:
// constructors and the literals of a type that says what its literals are;
// an integer's literal and a Double's are arith.constant's.
// Its grade is the one rule of where a constant stands
// (fold::constantStandsAt), which a constant the e-graph computes asks too:
// static data, used any number of times and, where its type holds
// references, held static, graded from what it holds, so nothing frees it
// and no count writes it; a small big, which has no cell, at any hold. A
// linear value of it is cast from it.
bool ConstantOp::isBuildableWith(Attribute value, Type type) {
  if (!fold::constantStandsAt(type, storageOf(value)))
    return false;
  auto constant = dyn_cast<ConstantAttrInterface>(value);
  return constant && constant.isBuildableAt(unrestricted(type));
}

LogicalResult ConstantOp::verify() {
  if (!isBuildableWith(getValue(), getType()))
    return emitOpError("cannot hold ")
           << getValue() << " as " << getType()
           << "; it holds constructors and the literals of strings, bigs and naturals, "
              "and integers and doubles are arith.constant";
  return success();
}

OpFoldResult ConstantOp::fold(FoldAdaptor) { return getValue(); }

LogicalResult ConstantOp::verifySymbolUses(SymbolTableCollection &symbols) {
  return verifyConstant(*this, symbols);
}
