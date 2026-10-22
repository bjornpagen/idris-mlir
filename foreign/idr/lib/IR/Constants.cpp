// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr.constant: the dialect's values, which hold no type, and the check of a
// constant through its fields and captures: a constructor against its data
// type's body, and a closure against its function's own signature, once per
// module verify through the collection the symbol-use walk hands over.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Families/Families.h"
#include "idr/IR/Fold.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Symbols.h"
#include "idr/Support/Footprint.h"

#include "mlir/IR/BuiltinTypes.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;
using namespace idr;

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

// That `closure`, a part of `type`, names a function that takes its
// captures, which wait on `parts`, each at its parameter's type. A constant
// closure gives no index terms, since one at terms stays fn.closure, so its
// function binds no index variable and its own signature is the one read.
// The symbol is resolved only here, so whether it binds any is checked
// here.
LogicalResult verifyClosure(Operation *op, SymbolTableCollection &symbols, ClosureAttr closure,
                            Type type, Parts &parts) {
  auto fn = symbols.lookupNearestSymbolFrom<FuncOp>(op, closure.getCallee());
  if (!fn)
    return op->emitOpError("has a closure of an unknown function ") << closure.getCallee();
  if (!fn.getBinders().getSorts().empty())
    return op->emitOpError("has a closure of ")
           << closure.getCallee() << ", which binds index variables a constant gives no terms";
  FunctionType at = fn.getFunctionType();
  ArrayRef<Type> inputs = at.getInputs();
  ArrayRef<Type> results = at.getResults();
  size_t captures = closure.getCaptures().size();
  if (captures > inputs.size())
    return op->emitOpError("has a closure with more captures than ")
           << closure.getCallee() << " has parameters";
  if (auto lazy = dyn_cast<LazyType>(type)) {
    // A suspension's function has no arguments past its captures: the cell
    // is the whole value, and forcing it passes nothing more. Counting
    // grades the function's return; the constant stays a plain cell, and
    // the carrier is what the two still share.
    if (captures != inputs.size() || results.size() != 1 ||
        unrestricted(results[0]) != unrestricted(lazy.getValue()))
      return op->emitOpError("has a suspension of ")
             << closure.getCallee() << ", where " << type << " is expected";
  } else {
    // The function's signature carries the grades reference counting
    // added. The constant names carriers that meet them at the quantities
    // Idris proved, each by the one rule a call's operands meet their
    // callee by, at the function's value from `first` on its `side`: an
    // axis the function's extents name may be static in its signature, while
    // the constant keeps the `?` Idris's type gives it.
    ExtentsAttr extents = fn.getExtentsAttr();
    auto partsMeet = [&](ExtentSide side, std::size_t first, ArrayRef<Type> view,
                         ArrayRef<Type> stated) {
      return view.size() == stated.size() &&
             llvm::all_of(llvm::enumerate(llvm::zip_equal(view, stated)), [&](auto indexed) {
               auto [index, pair] = indexed;
               auto [theirs, mine] = pair;
               return usesOf(theirs) == usesOf(mine) &&
                      meets(unrestricted(mine), unrestricted(theirs), extents, side,
                            static_cast<std::uint32_t>(first + index));
             });
    };
    auto actual = dyn_cast<FnType>(unrestricted(type));
    if (!actual ||
        !partsMeet(ExtentSide::Input, captures, inputs.drop_front(captures), actual.getInputs()) ||
        !partsMeet(ExtentSide::Result, 0, results, actual.getResults()))
      return op->emitOpError("has a closure of ")
             << closure.getCallee() << ", of type "
             << FnType::get(op->getContext(), inputs.drop_front(captures), results)
             << ", where " << type << " is expected";
  }
  // A constant fills a linear capture as its plain value.
  for (auto [capture, input] : llvm::zip(closure.getCaptures(), inputs.take_front(captures)))
    parts.push_back({capture, unrestricted(input)});
  return success();
}

// That `con`'s cells hold fields of their data type, which wait on
// `parts`. A constructor is checked a cell at a time, each field at its
// type in its own cell's application, however long its run, and never
// through the suffix that reading the field along its spine would build.
// Each cell after the first is the field along the spine of the one
// before, so its application is that field's type there, refined to the
// same constructor: a run of a vector's cells is checked at each cell's
// own index. One cell has no field after it.
LogicalResult verifyCon(Operation *op, ConAttr con, Parts &parts) {
  Tag tag = con.getTag();
  auto spine = static_cast<unsigned>(con.getSpine());
  DataType at = con.getData();
  StringRef label = at.ctor(tag).label;
  for (unsigned cell = 0, cells = con.getRunLength(); cell < cells; ++cell) {
    std::optional<SmallVector<Type>> fields = at.determinedFields(tag);
    if (!fields)
      return op->emitOpError("has a cell of @")
             << label << " at " << at << ", where its binders are not determined";
    // A constant fills a linear field as its plain value.
    for (auto [position, field] : llvm::enumerate(con.getCell(cell)))
      parts.push_back(
          {field, unrestricted((*fields)[con.fieldOfCell(cell, static_cast<unsigned>(position))])});
    if (cell + 1 == cells)
      break;
    auto next = dyn_cast<DataType>(unrestricted((*fields)[spine]));
    if (!next || next.getGroup() != at.getGroup() || next.getMember() != at.getMember())
      return op->emitOpError("has a run of @")
             << label << " along field " << spine << ", which holds no @" << label;
    at = next.refined({tag});
  }
  return success();
}

// That `value` is a constant of `type`, through every field and capture,
// with every symbol resolved. Each part is one the leaf rule of a
// constant's fields and captures accepts (fold::buildable), which the
// folders of constructors and closures ask too.
LogicalResult verifyConstant(Operation *op, SymbolTableCollection &symbols, Attribute value,
                             Type type) {
  Parts parts{Part(value, type)};
  Checked checked;
  while (!parts.empty()) {
    Part part = parts.back();
    parts.pop_back();
    if (!checked.try_emplace(part).second)
      continue;
    if (!fold::buildable(part.first, part.second))
      return op->emitOpError("has a constant ")
             << part.first << " where " << part.second << " is expected";
    // A string or a big holds nothing more to check.
    if (auto closure = dyn_cast<ClosureAttr>(part.first)) {
      if (failed(verifyClosure(op, symbols, closure, part.second, parts)))
        return failure();
    } else if (auto con = dyn_cast<ConAttr>(part.first)) {
      if (failed(verifyCon(op, con, parts)))
        return failure();
    }
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

// A big the runtime holds in its word, a small: no cell, so nothing a
// count could write.
bool inItsWord(Attribute value) {
  auto big = dyn_cast<BigAttr>(value);
  if (!big)
    return false;
  std::optional<int64_t> v = big.getValue().trySExtValue();
  return v && *v >= IDRIS_RT_SMALL_MIN && *v <= IDRIS_RT_SMALL_MAX;
}

} // namespace

// The kinds of value idr.constant holds: constructors, closures and the
// literals of a type that says what its literals are; an integer's literal
// and a Double's are arith.constant's. A constant is static data, used any
// number of times and, where its type holds references, held static,
// graded from what it holds: nothing frees it and no count writes it, as
// counting would a constant at a counted or scoped hold, though static
// data is read-only. A small big has no cell, so it stands at any hold. A
// linear value of it is cast from it.
bool ConstantOp::isBuildableWith(Attribute value, Type type) {
  Grade grade = gradeOf(type);
  if (grade.uses != Uses::Many)
    return false;
  if (grade.hold && grade.hold->release() != Release::Static && !inItsWord(value))
    return false;
  type = unrestricted(type);
  if (auto con = dyn_cast<ConAttr>(value))
    return dataTypeOf(type) == con.getData();
  if (isa<ClosureAttr>(value))
    return isa<FnType, LazyType>(type);
  // An integer and a Double are literals of their types too, but their
  // constant is upstream's, which every fold and pattern of arith reads:
  // one constant op per value.
  auto literal = dyn_cast<LiteralTypeInterface>(type);
  return literal && !isa<IntegerType, Float64Type>(type) && literal.isLiteral(value);
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
  return verifyConstant(*this, symbols, getValue(), unrestricted(getType()));
}
