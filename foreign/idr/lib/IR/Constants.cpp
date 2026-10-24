// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr.constant: the dialect's values, which hold no type, and the check of a
// constant through its fields and captures: a constructor against its data
// type's body, and a closure against its function's own signature, once per
// module verify through the collection the symbol-use walk hands over. Each
// constant answers for itself, through ConstantAttrInterface: at which
// types idr.constant holds it, how it is laid out as static data, how it
// holds closures, what it names and holds, and what a fold reads of it.
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
#include "idr/Support/Match.h"

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

// A constructor of `data` is held at a type whose data type is `data`.
bool holdsConstructor(DataType data, Type type) { return dataTypeOf(type) == data; }

// A constant closure is held at a type whose values carry labels, a
// closure's or a suspension's, as its type answers; verifyParts holds it to
// the one it is.
bool holdsClosure(Type type) {
  return match(
      carryingOf(type), [](const LabelCarrier &) { return true; },
      [](OneOf<carrying::Reference, carrying::Nothing> auto) { return false; });
}

// A literal of a type that says it is one of its literals: a big, and a
// string.
bool literalOf(Attribute value, Type type) {
  auto literal = dyn_cast<LiteralTypeInterface>(unrestricted(type));
  return literal && literal.isLiteral(value);
}

} // namespace

bool ConAttr::isBuildableAt(Type type) const { return holdsConstructor(getData(), type); }

bool ClosureAttr::isBuildableAt(Type type) const { return holdsClosure(type); }

// A constructor and a closure are static data, in a cell.
bool idr::fold::constructorStandsAt(const DataType &data, Type type) {
  return holdsConstructor(data, type) && constantStandsAt(type, Storage::Cell);
}

bool idr::fold::closureStandsAt(Type type) {
  return holdsClosure(type) && constantStandsAt(type, Storage::Cell);
}

// A big is a literal of the types that say a big is one of theirs: an
// Integer's, and a natural's where it is never negative.
bool BigAttr::isBuildableAt(Type type) const { return literalOf(*this, type); }

//===----------------------------------------------------------------------===//
// How a constant of ours holds closures
//===----------------------------------------------------------------------===//

// A constructor holds those its fields hold; a closure is one; a big holds
// none.
ClosureHolding ConAttr::getClosureHolding() const { return AttrOf<ConAttr>{*this}; }
ClosureHolding ClosureAttr::getClosureHolding() const { return AttrOf<ClosureAttr>{*this}; }
ClosureHolding BigAttr::getClosureHolding() const { return HoldsNoClosure{}; }

// An attribute that is no constant holds no closure.
ClosureHolding idr::closureHoldingOf(Attribute value) {
  auto constant = dyn_cast<ConstantAttrInterface>(value);
  return constant ? constant.getClosureHolding() : ClosureHolding(HoldsNoClosure{});
}

//===----------------------------------------------------------------------===//
// What a constant of ours names and holds
//===----------------------------------------------------------------------===//

// The closure names a function that takes its captures, each handed to
// `part` at its parameter's type. A constant closure gives no index terms,
// since one at terms stays fn.closure, so its function binds no index
// variable and its own signature is the one read. The symbol is resolved
// only here, so whether it binds any is checked here.
LogicalResult ClosureAttr::verifyParts(Operation *holder, SymbolTableCollection &symbols,
                                       Type type,
                                       function_ref<void(Attribute, Type)> part) const {
  auto fn = symbols.lookupNearestSymbolFrom<FuncOp>(holder, getCallee());
  if (!fn)
    return holder->emitOpError("has a closure of an unknown function ") << getCallee();
  if (!fn.getBinders().getSorts().empty())
    return holder->emitOpError("has a closure of ")
           << getCallee() << ", which binds index variables a constant gives no terms";
  FunctionType at = fn.getFunctionType();
  ArrayRef<Type> inputs = at.getInputs();
  ArrayRef<Type> results = at.getResults();
  size_t captures = getCaptures().size();
  if (captures > inputs.size())
    return holder->emitOpError("has a closure with more captures than ")
           << getCallee() << " has parameters";
  // The type it is held at carries a closure's labels or a suspension's,
  // which isBuildableAt has said; a type that carries neither is refused as
  // one no closure of this function is.
  auto misplaced = [&]() -> LogicalResult {
    return holder->emitOpError("has a closure of ")
           << getCallee() << ", of type "
           << FnType::get(getContext(), inputs.drop_front(captures), results) << ", where "
           << type << " is expected";
  };
  LogicalResult agrees = match(
      carryingOf(type),
      [&](const LabelCarrier &labels) {
        return match(
            labels,
            [&](const carrying::Suspension &suspension) -> LogicalResult {
              // A suspension's function has no arguments past its captures:
              // the cell is the whole value, and forcing it passes nothing
              // more. Counting grades the function's return; the constant
              // stays a plain cell, and the carrier is what the two still
              // share.
              LazyType lazy = suspension.type.get();
              if (captures != inputs.size() || results.size() != 1 ||
                  unrestricted(results[0]) != unrestricted(lazy.getValue()))
                return holder->emitOpError("has a suspension of ")
                       << getCallee() << ", where " << type << " is expected";
              return success();
            },
            [&](const carrying::Closure &closure) -> LogicalResult {
              // The function's signature carries the grades reference
              // counting added. The constant names carriers that meet them
              // at the quantities Idris proved, each by the one rule a
              // call's operands meet their callee by, at the function's
              // value from `first` on its `side`: an axis the function's
              // extents name may be static in its signature, while the
              // constant keeps the `?` Idris's type gives it.
              ExtentsAttr extents = fn.getExtentsAttr();
              auto partsMeet = [&](ExtentSide side, std::size_t first, ArrayRef<Type> view,
                                   ArrayRef<Type> stated) {
                return view.size() == stated.size() &&
                       llvm::all_of(llvm::enumerate(llvm::zip_equal(view, stated)),
                                    [&](auto indexed) {
                                      auto [index, pair] = indexed;
                                      auto [theirs, mine] = pair;
                                      return usesOf(theirs) == usesOf(mine) &&
                                             meets(unrestricted(mine), unrestricted(theirs),
                                                   extents, side,
                                                   static_cast<std::uint32_t>(first + index));
                                    });
              };
              FnType actual = closure.type.get();
              if (!partsMeet(ExtentSide::Input, captures, inputs.drop_front(captures),
                             actual.getInputs()) ||
                  !partsMeet(ExtentSide::Result, 0, results, actual.getResults()))
                return misplaced();
              return success();
            });
      },
      [&](OneOf<carrying::Reference, carrying::Nothing> auto) -> LogicalResult {
        return misplaced();
      });
  if (failed(agrees))
    return failure();
  // A capture is the closure's part as a field is a constructor's, at the
  // type the product rule gives it (fieldType): used as often as the
  // closure times the parameter's own uses, holding what the closure holds.
  // So a constant fills a linear capture as its plain value, static data as
  // the closure is.
  for (auto [capture, input] : llvm::zip(getCaptures(), inputs.take_front(captures)))
    part(capture, fieldType(type, unrestricted(input), usesOf(input), fieldReach(input)));
  return success();
}

// The constructor's cells hold fields of its data type, each handed to
// `part` at the type the product rule gives it (fieldType), as a match
// binds it: used as often as the cell holding it times the field's own
// uses, holding what the cell holds as far as the cell's claim reaches into
// it. So a constant fills a linear field as its plain value, and a field of
// static data is static data. Its data type is the type it is held at,
// which isBuildableAt has said. A constructor is checked a cell at a time,
// each field at its type in its own cell's application, however long its
// run, and never through the suffix that reading the field along its spine
// would build. Each cell after the first is the field along the spine of
// the one before, held as that field is, so its application is that
// field's type there, refined to the same constructor: a run of a vector's
// cells is checked at each cell's own index. One cell has no field after
// it.
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

// A closure reaches static data only as its label's constructor:
// defunctionalization rewrites every constant closure into one before
// anything is laid out.
StaticForm ClosureAttr::getStaticForm(Type) const {
  llvm::reportFatalInternalError(
      "a closure laid out as static data, which defunctionalization makes its label's "
      "constructor first");
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

// A big's integer; a constructor and a closure whole.
FoldValue BigAttr::getFoldValue() const { return fold_value::Big{{*this}}; }
FoldValue ConAttr::getFoldValue() const { return fold_value::Whole{}; }
FoldValue ClosureAttr::getFoldValue() const { return fold_value::Whole{}; }

//===----------------------------------------------------------------------===//
// Upstream's constants
//===----------------------------------------------------------------------===//

namespace {

// What every upstream constant answers alike: it names nothing, so it has no
// part to check, and it holds no closure.
template <class Model, class A>
struct UpstreamConstant : ConstantAttrInterface::ExternalModel<Model, A> {
  LogicalResult verifyParts(Attribute, Operation *, SymbolTableCollection &, Type,
                            function_ref<void(Attribute, Type)>) const {
    return success();
  }
  ClosureHolding getClosureHolding(Attribute) const { return HoldsNoClosure{}; }
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

// A part of a constant, a field or a capture, and the type it is checked
// at.
using Part = std::pair<Attribute, Type>;

// The parts still to check. A constant is as deep as the program's text
// makes it, so its parts wait here rather than on the stack.
using Parts = footprint::Vector<Part>;

// The parts already checked: a constant shares its parts, and each is
// checked once. Its keys are uniqued attributes and types, the parts'
// content, never a node of the IR.
using Checked = footprint::DenseMap<Part, llvm::detail::DenseSetEmpty, llvm::DenseMapInfo<Part>,
                                    llvm::detail::DenseSetPair<Part>>;

// That `op` holds a constant of its type, through every field and capture,
// with every symbol resolved. The constant stands at the op's type, which
// the op's verifier has judged; each part stands at the type its holder
// hands it, by the product rule, and is one the leaf rule of a constant's
// fields and captures accepts (fold::buildable), which the folders of
// constructors and closures ask too of the values they take, so it is a
// constant, which then checks what it names and hands over its parts: a
// string, an integer or a Double names none.
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

// A field or capture of a constant holds a word or a Double of exactly its
// type, or a value idr.constant holds at it. An array is neither: a dense
// tensor is a value of its own, which arith.constant builds and no constant
// constructor holds, so a constructor around one stays an op.
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
// constructors, closures and the literals of a type that says what its
// literals are; an integer's literal and a Double's are arith.constant's.
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
           << "; it holds constructors, closures and the literals of strings, bigs and "
              "naturals, and integers and doubles are arith.constant";
  return success();
}

OpFoldResult ConstantOp::fold(FoldAdaptor) { return getValue(); }

LogicalResult ConstantOp::verifySymbolUses(SymbolTableCollection &symbols) {
  return verifyConstant(*this, symbols);
}
