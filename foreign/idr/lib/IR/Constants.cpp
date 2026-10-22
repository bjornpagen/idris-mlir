// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr.constant: the dialect's values, which hold no type, and the check of a
// constant through its fields and captures: a constructor against its data
// type's body, and a closure against its function's signature, once per
// module verify through the collection the symbol-use walk hands over.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Families/Families.h"
#include "idr/IR/Fold.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Symbols.h"
#include "idr/Support/Footprint.h"

#include "llvm/ADT/DenseSet.h"

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
// captures, which wait on `parts`, each at its parameter's type.
LogicalResult verifyClosure(Operation *op, SymbolTableCollection &symbols, ClosureAttr closure,
                            Type type, Parts &parts) {
  auto fn = symbols.lookupNearestSymbolFrom<FuncOp>(op, closure.getCallee());
  if (!fn)
    return op->emitOpError("has a closure of an unknown function ") << closure.getCallee();
  ArrayRef<Type> inputs = fn.getArgumentTypes();
  size_t captures = closure.getCaptures().size();
  if (captures > inputs.size())
    return op->emitOpError("has a closure with more captures than ")
           << closure.getCallee() << " has parameters";
  if (auto lazy = dyn_cast<LazyType>(type)) {
    // A suspension's function has no arguments past its captures: the cell
    // is the whole value, and forcing it passes nothing more. idr-rc grades
    // the function's return; the constant stays a plain cell, and the
    // carrier is what the two still share.
    if (captures != inputs.size() || fn.getResultTypes().size() != 1 ||
        unrestricted(fn.getResultTypes()[0]) != unrestricted(lazy.getValue()) ||
        llvm::any_of(inputs, isWorld))
      return op->emitOpError("has a suspension of ")
             << closure.getCallee() << ", where " << type << " is expected";
  } else {
    // The function's signature carries the grades reference counting
    // added. The constant names the same carriers at the quantities Idris
    // proved.
    auto actual = dyn_cast<FnType>(unrestricted(type));
    if (!actual || !sameCarriers(inputs.drop_front(captures), actual.getInputs()) ||
        !sameCarriers(fn.getResultTypes(), actual.getResults()))
      return op->emitOpError("has a closure of ")
             << closure.getCallee() << ", of type "
             << FnType::get(op->getContext(), inputs.drop_front(captures), fn.getResultTypes())
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

// The kinds of value idr.constant holds: constructors, closures and the
// literals of a type that says what its literals are; an integer's literal
// is arith.constant's. A constant is static data: used any number of times,
// and where its type holds references, held static, graded from what it
// holds, which nothing frees. A linear value of it is cast from it.
bool ConstantOp::isBuildableWith(Attribute value, Type type) {
  Grade grade = gradeOf(type);
  if (grade.uses != Uses::Many || (grade.hold && grade.hold->release() != Release::Static))
    return false;
  type = unrestricted(type);
  if (auto con = dyn_cast<ConAttr>(value))
    return dataTypeOf(type) == con.getData();
  if (isa<ClosureAttr>(value))
    return isa<FnType, LazyType>(type);
  // An integer is a literal of its type too, but its constant is upstream's,
  // which every fold and pattern of arith reads: one constant op per value.
  auto literal = dyn_cast<LiteralTypeInterface>(type);
  return literal && !isa<IntegerType>(type) && literal.isLiteral(value);
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
