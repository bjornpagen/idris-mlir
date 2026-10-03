// idr.match and idr.match_lit: their syntax, their rules, and the region
// each takes, as a RegionBranchOpInterface.

#include "idr/Idr.h"

#include "mlir/IR/Matchers.h"
#include "mlir/IR/OpImplementation.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/TypeSwitch.h"

import idr.ops;

using namespace mlir;
using namespace idr;

// `idr.match %v : T -> (R...) { case @C(%x: A) {...} ... default {...} }`
ParseResult MatchOp::parse(OpAsmParser &parser, OperationState &result) {
  Type scrutineeType;
  SmallVector<Attribute> cases;
  if (ops::parseMatchHead(parser, result, scrutineeType) ||
      ops::parseMatchBody(parser, result, [&](Region &region) -> ParseResult {
        StringAttr name;
        SmallVector<OpAsmParser::Argument> fields;
        if (parser.parseSymbolName(name) ||
            parser.parseArgumentList(fields, OpAsmParser::Delimiter::Paren,
                                     /*allowType=*/true) ||
            parser.parseRegion(region, fields))
          return failure();
        cases.push_back(FlatSymbolRefAttr::get(name));
        return success();
      }))
    return failure();
  result.getOrAddProperties<Properties>().cases = parser.getBuilder().getArrayAttr(cases);
  return success();
}

void MatchOp::print(OpAsmPrinter &printer) {
  ops::printMatch(*this, printer, [&](unsigned index) {
    printer << getCases()[index] << '(';
    llvm::interleaveComma(getCaseRegion(index).getArguments(), printer,
                          [&](BlockArgument arg) { printer.printRegionArgument(arg); });
    printer << ')';
  });
}

LogicalResult MatchOp::verify() {
  size_t cases = getCases().size();
  if (getRegions().size() != cases && getRegions().size() != cases + 1)
    return emitOpError("expects one region per case and at most one default");
  llvm::SmallDenseSet<Attribute> seen;
  for (Attribute name : getCases()) {
    if (!isa<FlatSymbolRefAttr>(name))
      return emitOpError("expects constructor names as cases, got ") << name;
    if (!seen.insert(name).second)
      return emitOpError("has two cases for ") << name;
  }
  if (Region *fallback = getDefaultRegion()) {
    TypeRange args = fallback->getArgumentTypes();
    if (args.size() > 1 || (args.size() == 1 && args.front() != getScrutinee().getType()))
      return emitOpError("expects a default region without arguments, or one that takes the "
                         "scrutinee back at its type");
  }
  return ops::verifyMatchRegions(*this);
}

// Each case is a constructor of the scrutinee's type, and its region's
// arguments are that constructor's fields at the scrutinee's grade.
LogicalResult MatchOp::verifySymbolUses(SymbolTableCollection &symbols) {
  auto data =
      symbols.lookupNearestSymbolFrom<DataOp>(*this, getSumName(getScrutinee().getType()));
  for (auto [index, name] : llvm::enumerate(getCases().getAsRange<FlatSymbolRefAttr>())) {
    CtorOp ctor = lookupCtor(data, name.getValue());
    if (!ctor)
      return emitOpError("has a case for ")
             << name << ", which is not a constructor of " << getScrutinee().getType();
    SmallVector<Type> expected;
    for (Type field : ctor.getFieldTypes().getAsValueRange<TypeAttr>())
      expected.push_back(fieldType(getScrutinee().getType(), field));
    TypeRange args = getCaseRegion(static_cast<unsigned>(index)).getArgumentTypes();
    if (args != TypeRange(expected))
      return emitOpError("case ") << name << " must take the constructor's fields at the "
                                  << "scrutinee's grade, " << expected;
  }
  return success();
}

// A constant constructor, or the constructor of the idr.con that built the
// scrutinee, also through a linear position; else what an enclosing match
// on the same value established.
Region *MatchOp::getTakenRegion(Attribute value) {
  SymbolRefAttr ctor;
  Value source = throughLinear(getScrutinee());
  ConAttr constant;
  if (auto con = dyn_cast_or_null<ConAttr>(value))
    ctor = con.getCtor();
  else if (auto built = source.getDefiningOp<ConOp>())
    ctor = built.getCtor();
  else if (matchPattern(source, m_Constant(&constant)))
    ctor = constant.getCtor();
  if (!ctor)
    return ops::takenFromEnclosing(*this);
  return ops::takenRegion(*this, FlatSymbolRefAttr::get(ctor.getLeafReference()));
}

// `idr.match_lit %n : T -> (R...) { case 0 {...} ... default {...} }`
ParseResult MatchLitOp::parse(OpAsmParser &parser, OperationState &result) {
  Type type;
  SmallVector<Attribute> cases;
  auto parseKey = [&]() -> FailureOr<Attribute> {
    if (auto integer = dyn_cast<IntegerType>(type)) {
      if (integer.getWidth() == 1) {
        if (succeeded(parser.parseOptionalKeyword("true")))
          return Attribute(IntegerAttr::get(integer, 1));
        if (succeeded(parser.parseOptionalKeyword("false")))
          return Attribute(IntegerAttr::get(integer, 0));
      }
      APInt value;
      SMLoc loc = parser.getCurrentLocation();
      if (parser.parseInteger(value))
        return failure();
      unsigned width = integer.getWidth();
      if ((value.isNegative() ? value.getSignificantBits() : value.getActiveBits()) > width)
        return parser.emitError(loc, "key does not fit in ") << type;
      return Attribute(IntegerAttr::get(
          integer, value.isNegative() ? value.sextOrTrunc(width) : value.zextOrTrunc(width)));
    }
    if (isa<StrType>(type)) {
      std::string bytes;
      if (parser.parseString(&bytes))
        return failure();
      return Attribute(parser.getBuilder().getStringAttr(bytes));
    }
    if (!isa<BigType, NatType>(type))
      return parser.emitError(parser.getCurrentLocation(), "a literal match on ")
             << type << " has no keys";
    BigAttr big;
    if (parser.parseAttribute(big))
      return failure();
    return Attribute(big);
  };
  if (ops::parseMatchHead(parser, result, type) ||
      ops::parseMatchBody(parser, result, [&](Region &region) -> ParseResult {
        FailureOr<Attribute> key = parseKey();
        if (failed(key) || parser.parseRegion(region))
          return failure();
        cases.push_back(*key);
        return success();
      }))
    return failure();
  result.getOrAddProperties<Properties>().cases = parser.getBuilder().getArrayAttr(cases);
  return success();
}

void MatchLitOp::print(OpAsmPrinter &printer) {
  ops::printMatch(*this, printer,
             [&](unsigned index) { printer.printAttributeWithoutType(getCases()[index]); });
}

// Keys are distinct literals of the scrutinee's type, and a default is required.
LogicalResult MatchLitOp::verify() {
  if (getRegions().size() != getCases().size() + 1)
    return emitOpError("expects one region per case and a default");
  Type type = getScrutinee().getType();
  llvm::SmallDenseSet<Attribute> seen;
  for (Attribute key : getCases()) {
    bool typed = TypeSwitch<Type, bool>(type)
                     .Case([&](IntegerType) {
                       auto integer = dyn_cast<IntegerAttr>(key);
                       return integer && integer.getType() == type;
                     })
                     .Case([&](StrType) { return isa<StringAttr>(key); })
                     .Case([&](BigType) { return isa<BigAttr>(key); })
                     .Case([&](NatType) {
                       auto big = dyn_cast<BigAttr>(key);
                       return big && !big.getValue().starts_with("-");
                     })
                     .Default([](Type) { return false; });
    if (!typed)
      return emitOpError("has a key ") << key << " that is not a literal of " << type;
    if (!seen.insert(key).second)
      return emitOpError("has two cases for ") << key;
  }
  for (Region &region : getRegions())
    if (region.getNumArguments())
      return emitOpError("expects regions without arguments");
  return ops::verifyMatchRegions(*this);
}

// The literal itself, else what an enclosing match on the same value
// established.
Region *MatchLitOp::getTakenRegion(Attribute value) {
  if (!value)
    return ops::takenFromEnclosing(*this);
  return ops::takenRegion(*this, value);
}

// RegionBranchOpInterface, as scf.index_switch (idr.ops).
void MatchOp::getSuccessorRegions(RegionBranchPoint point,
                                  SmallVectorImpl<RegionSuccessor> &successors) {
  ops::matchSuccessors(*this, point, successors);
}

void MatchOp::getEntrySuccessorRegions(ArrayRef<Attribute> operands,
                                       SmallVectorImpl<RegionSuccessor> &successors) {
  ops::matchEntrySuccessors(*this, getTakenRegion(operands.front()), successors);
}

void MatchOp::getRegionInvocationBounds(ArrayRef<Attribute> operands,
                                        SmallVectorImpl<InvocationBounds> &bounds) {
  ops::matchInvocationBounds(*this, getTakenRegion(operands.front()), bounds);
}

ValueRange MatchOp::getSuccessorInputs(RegionSuccessor successor) {
  return successor.isOperation() ? ValueRange(getResults()) : ValueRange();
}

void MatchLitOp::getSuccessorRegions(RegionBranchPoint point,
                                     SmallVectorImpl<RegionSuccessor> &successors) {
  ops::matchSuccessors(*this, point, successors);
}

void MatchLitOp::getEntrySuccessorRegions(ArrayRef<Attribute> operands,
                                          SmallVectorImpl<RegionSuccessor> &successors) {
  ops::matchEntrySuccessors(*this, getTakenRegion(operands.front()), successors);
}

void MatchLitOp::getRegionInvocationBounds(ArrayRef<Attribute> operands,
                                           SmallVectorImpl<InvocationBounds> &bounds) {
  ops::matchInvocationBounds(*this, getTakenRegion(operands.front()), bounds);
}

ValueRange MatchLitOp::getSuccessorInputs(RegionSuccessor successor) {
  return successor.isOperation() ? ValueRange(getResults()) : ValueRange();
}
