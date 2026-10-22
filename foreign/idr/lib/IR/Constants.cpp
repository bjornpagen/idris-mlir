// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr.constant: the dialect's values, which hold no type, and the check of a
// constant through its fields and captures: a constructor against its data
// type's body, and a closure against its function's signature, once per
// module verify through the collection the symbol-use walk hands over.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Fold.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Symbols.h"

#include "llvm/ADT/DenseSet.h"

using namespace mlir;
using namespace idr;

namespace {

// The constants and types already checked: a constant shares its parts, and
// each is checked once.
using Checked = llvm::DenseSet<std::pair<Attribute, Type>>;

LogicalResult verifyConstant(Operation *op, SymbolTableCollection &symbols, Attribute value,
                             Type type, Checked &checked);

LogicalResult verifyConstants(Operation *op, SymbolTableCollection &symbols,
                              ArrayAttr values, TypeRange types, Checked &checked) {
  if (values.size() != types.size())
    return op->emitOpError("has a constant with ")
           << values.size() << " fields or captures where " << types.size()
           << " are expected";
  // A constant fills a linear field or capture as its plain value.
  for (auto [value, type] : llvm::zip(values, types))
    if (failed(verifyConstant(op, symbols, value, unrestricted(type), checked)))
      return failure();
  return success();
}

// That `closure`, a constant of `type`, names a function that takes its
// captures.
LogicalResult verifyClosure(Operation *op, SymbolTableCollection &symbols, ClosureAttr closure,
                            Type type, Checked &checked) {
  auto fn = symbols.lookupNearestSymbolFrom<FuncOp>(op, closure.getCallee());
  if (!fn)
    return op->emitOpError("has a closure of an unknown function ") << closure.getCallee();
  ArrayRef<Type> inputs = fn.getArgumentTypes();
  size_t captures = closure.getCaptures().size();
  if (captures > inputs.size())
    return op->emitOpError("has a closure with more captures than ")
           << closure.getCallee() << " has parameters";
  // A suspension's function has no arguments past its captures: the cell
  // is the whole value, and forcing it passes nothing more.
  if (auto lazy = dyn_cast<LazyType>(type)) {
    // idr-rc grades the function's return; the constant stays a plain
    // cell, and the carrier is what the two still share.
    if (captures != inputs.size() || fn.getResultTypes().size() != 1 ||
        unrestricted(fn.getResultTypes()[0]) != unrestricted(lazy.getValue()) ||
        llvm::any_of(inputs, isWorld))
      return op->emitOpError("has a suspension of ")
             << closure.getCallee() << ", where " << type << " is expected";
    return verifyConstants(op, symbols, closure.getCaptures(), inputs, checked);
  }
  // The function's signature carries the grades reference counting added.
  // The constant names the same carriers at the quantities Idris proved.
  auto actual = dyn_cast<FnType>(unrestricted(type));
  if (!actual || !sameCarriers(inputs.drop_front(captures), actual.getInputs()) ||
      !sameCarriers(fn.getResultTypes(), actual.getResults()))
    return op->emitOpError("has a closure of ")
           << closure.getCallee() << ", of type "
           << FnType::get(op->getContext(), inputs.drop_front(captures), fn.getResultTypes())
           << ", where " << type << " is expected";
  return verifyConstants(op, symbols, closure.getCaptures(), inputs.take_front(captures),
                         checked);
}

// That `value` is a constant of `type`, recursively through fields and
// captures, with every symbol resolved. Each part is one the leaf rule of a
// constant's fields and captures accepts (fold::buildable), which the
// folders of constructors and closures ask too. A constructor is checked a
// cell at a time, each field at its field's type, however long its run, and
// never through the suffix that reading the field along its spine would
// build. Each (value, type) is checked once.
LogicalResult verifyConstant(Operation *op, SymbolTableCollection &symbols, Attribute value,
                             Type type, Checked &checked) {
  if (!checked.insert({value, type}).second)
    return success();
  if (!fold::buildable(value, type))
    return op->emitOpError("has a constant ") << value << " where " << type << " is expected";
  if (auto closure = dyn_cast<ClosureAttr>(value))
    return verifyClosure(op, symbols, closure, type, checked);
  // A string or a big holds nothing more to check.
  auto con = dyn_cast<ConAttr>(value);
  if (!con)
    return success();
  const Ctor &ctor = con.getCtor();
  // Each cell after the first is the field along the spine of the one
  // before, so that field holds the constant's own type. One cell has no
  // field after it.
  unsigned spine = con.getSpine();
  if (con.getRunLength() > 1 && unrestricted(ctor.fields[spine]) != type)
    return op->emitOpError("has a run of @")
           << ctor.name.getValue() << " along field " << spine << ", which does not hold "
           << type;
  for (auto [cell, fields] : llvm::enumerate(con.getCells()))
    for (auto [position, field] : llvm::enumerate(fields)) {
      unsigned index =
          con.fieldOfCell(static_cast<unsigned>(cell), static_cast<unsigned>(position));
      // A constant fills a linear field as its plain value.
      if (failed(verifyConstant(op, symbols, field, unrestricted(ctor.fields[index]), checked)))
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
  Checked checked;
  return verifyConstant(*this, symbols, getValue(), unrestricted(getType()), checked);
}
