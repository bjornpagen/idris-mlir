// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr.constant: the dialect's values, stored untyped, and the check of a
// constant through its fields and captures: a constructor against its data
// type's body, and a closure against its function's signature, once per
// module verify through the collection the symbol-use walk hands over.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"

#include "mlir/IR/OpImplementation.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/TypeSwitch.h"

using namespace mlir;
using namespace idr;

namespace {

// A value without the type that MLIR's parser reads into it (Idr_Attr): the
// form in which values are stored. A run is rebuilt from its cells and its
// tail in one step, not a cell at a time.
Attribute untyped(Attribute value) {
  MLIRContext *ctx = value.getContext();
  return TypeSwitch<Attribute, Attribute>(value)
      .Case([&](ConAttr con) {
        if (con.isRun())
          return ConAttr::getRun(ctx, con.getData(), con.getTag(), con.getSpine(),
                                 con.getRunCells(), con.getTail());
        return ConAttr::get(ctx, con.getData(), con.getTag(), con.getFields());
      })
      .Case([&](ClosureAttr closure) {
        return ClosureAttr::get(ctx, closure.getCallee(), closure.getCaptures());
      })
      .Case([&](BigAttr big) { return BigAttr::get(ctx, big.getValue()); })
      .Case([&](StringAttr str) { return StringAttr::get(ctx, str.getValue()); })
      .Default([](Attribute other) { return other; });
}

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

// That `value`, a constant of `type` other than a constructor, names
// functions that take its captures.
LogicalResult verifyClosure(Operation *op, SymbolTableCollection &symbols, Attribute value,
                            Type type, Checked &checked) {
  auto closure = dyn_cast<ClosureAttr>(value);
  if (!closure)
    return success();
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
// captures, with every symbol resolved. A run's tail is the next value of
// the loop, after its cells: a list is checked a cell at a time however long
// it is, and never through the suffix that reading the field along its spine
// would build.
LogicalResult verifyConstant(Operation *op, SymbolTableCollection &symbols, Attribute value,
                             Type type, Checked &checked) {
  while (checked.insert({value, type}).second) {
    if (auto scalar = dyn_cast<TypedAttr>(value);
        scalar && isa<IntegerAttr, FloatAttr>(value) && scalar.getType() == type &&
        isFieldType(type))
      return success();
    if (!ConstantOp::isBuildableWith(value, type))
      return op->emitOpError("has a constant ") << value << " where " << type << " is expected";
    auto con = dyn_cast<ConAttr>(value);
    if (!con)
      return verifyClosure(op, symbols, value, type, checked);
    const Ctor &ctor = con.getCtor();
    SmallVector<Type> fields(ctor.fields);
    if (!con.isRun())
      return verifyConstants(op, symbols, con.getFields(), fields, checked);
    // Each cell after the first is the field along the spine of the one
    // before, so that field holds the constructor's own type.
    unsigned spine = con.getSpine();
    if (spine >= fields.size() || unrestricted(fields[spine]) != type)
      return op->emitOpError("has a run of @")
             << ctor.name.getValue() << " along field " << spine << ", which does not hold "
             << type;
    fields.erase(fields.begin() + spine);
    for (ArrayAttr cell : con.getRunCells())
      if (failed(verifyConstants(op, symbols, cell, fields, checked)))
        return failure();
    value = con.getTail();
  }
  return success();
}

} // namespace

// The kinds of value idr.constant holds, stored untyped; scalars are
// arith.constant's. A constant is static data, read in place: used any
// number of times, plain before idr-rc and its view (Borrow) after it. A
// linear value of it is entered from it, an owned one taken (idr.dup).
bool ConstantOp::isBuildableWith(Attribute value, Type type) {
  if (untyped(value) != value || gradeOf(type).quantity != Quantity::Many || isOwned(type))
    return false;
  type = unrestricted(type);
  if (auto con = dyn_cast<ConAttr>(value))
    return dataTypeOf(type) == con.getData();
  return (isa<ClosureAttr>(value) && (isa<FnType>(type) || isa<LazyType>(type))) ||
         (isa<BigAttr>(value) && isa<BigType>(type)) ||
         // A natural constant is never negative: the type proves it.
         (isa<BigAttr>(value) && isa<NatType>(type) &&
          !cast<BigAttr>(value).getValue().isNegative()) ||
         (isa<StringAttr>(value) && isa<StrType>(type));
}

// `idr.constant <value> : <type>`: MLIR's parser reads the type into the
// value, from which it becomes the result's.
ParseResult ConstantOp::parse(OpAsmParser &parser, OperationState &result) {
  Attribute value;
  SMLoc loc = parser.getCurrentLocation();
  if (parser.parseAttribute(value))
    return failure();
  auto typed = dyn_cast<TypedAttr>(value);
  if (!typed)
    return parser.emitError(loc, "expects a value followed by `:` and its type");
  Type type = typed.getType();
  // The parser hands the type after an attribute to the attribute's own
  // parser, but not the type after an alias of one (a large constant is
  // printed as an alias), which is then left for us.
  if (isa<NoneType>(type) && (parser.parseOptionalColon() || parser.parseType(type)))
    return parser.emitError(loc, "expects a value followed by `:` and its type");
  result.addTypes(type);
  result.getOrAddProperties<Properties>().value = untyped(value);
  SMLoc attrsLoc = parser.getCurrentLocation();
  if (parser.parseOptionalAttrDict(result.attributes))
    return failure();
  // The value is the syntax's, set as a property above; a `value` in the
  // dict would become that property when the op is created, silently in
  // place of the one written. Check the dict's inherent facts first, as
  // the generic parser does, and refuse the restated one.
  if (failed(verifyInherentAttrs(result.name, result.attributes, [&]() {
        return parser.emitError(attrsLoc);
      })))
    return failure();
  if (result.attributes.get("value"))
    return parser.emitError(attrsLoc, "inherent attribute 'value' cannot be parsed from "
                                      "attr-dict when strict properties in assembly format "
                                      "is enabled");
  return success();
}

void ConstantOp::print(OpAsmPrinter &printer) {
  printer << ' ';
  printer.printAttributeWithoutType(getValue());
  printer << " : " << getType();
  printer.printOptionalAttrDict((*this)->getAttrs(), {"value"});
}

LogicalResult ConstantOp::verify() {
  if (!isBuildableWith(getValue(), getType()))
    return emitOpError("cannot hold ")
           << getValue() << " as " << getType()
           << "; it holds constructors, closures, strings, bigs and naturals that are not "
              "negative, untyped, and integers and doubles are arith.constant";
  return success();
}

OpFoldResult ConstantOp::fold(FoldAdaptor) { return getValue(); }

LogicalResult ConstantOp::verifySymbolUses(SymbolTableCollection &symbols) {
  Checked checked;
  return verifyConstant(*this, symbols, getValue(), unrestricted(getType()), checked);
}
