// idr.constant: the dialect's values, stored untyped, and the check of
// every symbol a constant names.

#include "idr/Idr.h"

#include "mlir/IR/OpImplementation.h"

import idr.ops;

using namespace mlir;
using namespace idr;

// The kinds of value idr.constant holds, stored untyped; scalars are
// arith.constant's.
bool ConstantOp::isBuildableWith(Attribute value, Type type) {
  if (ops::untyped(value) != value)
    return false;
  // The erased value is at its own grade. Every other constant is
  // unrestricted: a static value is used any number of times, and a
  // linear value of it is entered from it, an owned one taken (idr.dup).
  if (isa<ErasedAttr>(value))
    return isErased(type);
  if (type != unrestricted(type))
    return false;
  if (auto con = dyn_cast<ConAttr>(value)) {
    FlatSymbolRefAttr name = getSumName(type);
    return name && name.getAttr() == con.getCtor().getRootReference();
  }
  return (isa<ClosureAttr>(value) && isa<FnType>(type)) ||
         (isa<BigAttr>(value) && isa<BigType>(type)) ||
         // A natural constant is never negative: the type proves it.
         (isa<BigAttr>(value) && isa<NatType>(type) &&
          !cast<BigAttr>(value).getValue().starts_with("-")) ||
         (isa<ErasedAttr>(value) && isErased(type)) ||
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
  result.getOrAddProperties<Properties>().value = ops::untyped(value);
  return parser.parseOptionalAttrDict(result.attributes);
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
           << "; it holds constructors, closures, strings, bigs, naturals that are not "
              "negative and the erased value, "
              "untyped, and integers and doubles are arith.constant";
  return success();
}

OpFoldResult ConstantOp::fold(FoldAdaptor) { return getValue(); }

LogicalResult ConstantOp::verifySymbolUses(SymbolTableCollection &symbols) {
  ops::Checked checked;
  return ops::verifyConstant(*this, symbols, getValue(), getType(), checked);
}
