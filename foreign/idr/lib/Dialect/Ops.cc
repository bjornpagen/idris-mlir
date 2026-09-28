// The idr ops: syntax, verifiers, folders and interfaces
// (docs/cutover.md, sections 10.3 and 10.5).

#include "idr/Idr.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/Matchers.h"
#include "mlir/IR/OpImplementation.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/TypeSwitch.h"

#include <concepts>

using namespace mlir;
using namespace idr;

//===----------------------------------------------------------------------===//
// Facts that rule out a crash (IDR-EFF-1)
//===----------------------------------------------------------------------===//

bool idr::knownNonZero(Value value) {
  Attribute constant;
  if (!matchPattern(value, m_Constant(&constant)))
    return false;
  if (auto integer = dyn_cast<IntegerAttr>(constant))
    return !integer.getValue().isZero();
  if (auto big = dyn_cast<BigAttr>(constant))
    return big.getValue() != "0";
  return false;
}

bool idr::knownFinite(Value value) {
  FloatAttr constant;
  return matchPattern(value, m_Constant(&constant)) && constant.getValue().isFinite();
}

bool idr::knownNonEmpty(Value value) {
  StringAttr constant;
  if (matchPattern(value, m_Constant(&constant)))
    return !constant.getValue().empty();
  Operation *def = value.getDefiningOp();
  if (isa_and_nonnull<StrConsOp, StrFromCharOp, StrShowOp, BigShowOp>(def))
    return true;
  if (auto append = dyn_cast_or_null<StrAppendOp>(def))
    return knownNonEmpty(append.getLhs()) || knownNonEmpty(append.getRhs());
  return false;
}

//===----------------------------------------------------------------------===//
// Custom directives
//===----------------------------------------------------------------------===//

namespace {

// `signed`, `unsigned` or nothing: how an op reads its integer operand. Only
// `signed` is kept, as a unit attribute, and printed.
ParseResult parseSignedness(OpAsmParser &parser, UnitAttr &isSigned) {
  if (succeeded(parser.parseOptionalKeyword("signed")))
    isSigned = parser.getBuilder().getUnitAttr();
  else
    (void)parser.parseOptionalKeyword("unsigned");
  return success();
}

void printSignedness(OpAsmPrinter &printer, Operation *, UnitAttr isSigned) {
  if (isSigned)
    printer << "signed ";
}

// The field types of a constructor: `(i64, f64)`.
ParseResult parseFieldTypes(OpAsmParser &parser, ArrayAttr &fieldTypes) {
  SmallVector<Attribute> types;
  if (parser.parseCommaSeparatedList(OpAsmParser::Delimiter::Paren, [&] {
        Type type;
        if (parser.parseType(type))
          return failure();
        types.push_back(TypeAttr::get(type));
        return success();
      }))
    return failure();
  fieldTypes = parser.getBuilder().getArrayAttr(types);
  return success();
}

void printFieldTypes(OpAsmPrinter &printer, Operation *, ArrayAttr fieldTypes) {
  printer << '(';
  llvm::interleaveComma(fieldTypes.getAsValueRange<TypeAttr>(), printer);
  printer << ')';
}

//===----------------------------------------------------------------------===//
// Division (IDR-DIV-*), shared by idr.div and idr.mod through IdrOps.td
//===----------------------------------------------------------------------===//

// Euclidean quotient and remainder (SEM-INT-3) on the mathematical values of
// `a` and `b` in `width` bits; the quotient wraps.
std::pair<APInt, APInt> idrisDivMod(const APInt &a, const APInt &b, bool isSigned) {
  if (!isSigned)
    return {a.udiv(b), a.urem(b)};
  if (a.isMinSignedValue() && b.isAllOnes())
    return {a, APInt::getZero(a.getBitWidth())};
  APInt q = a.sdiv(b), r = a.srem(b);
  if (r.isNegative()) {
    if (b.isStrictlyPositive()) {
      q -= 1;
      r += b;
    } else {
      q += 1;
      r -= b;
    }
  }
  return {q, r};
}

template <typename Division>
concept DivisionOp = requires(Division op) {
  { Division::quotient } -> std::convertible_to<bool>;
  op.getLhs();
  op.getRhs();
  op.getIsSigned();
};

template <DivisionOp Division>
OpFoldResult foldDivision(Division op, typename Division::FoldAdaptor adaptor) {
  auto rhs = dyn_cast_or_null<IntegerAttr>(adaptor.getRhs());
  if (!rhs || rhs.getValue().isZero())
    return {};
  if (rhs.getValue().isOne())
    return Division::quotient ? OpFoldResult(op.getLhs())
                              : OpFoldResult(IntegerAttr::get(op.getType(), 0));
  auto lhs = dyn_cast_or_null<IntegerAttr>(adaptor.getLhs());
  if (!lhs)
    return {};
  auto [q, r] = idrisDivMod(lhs.getValue(), rhs.getValue(), op.getIsSigned());
  return IntegerAttr::get(op.getType(), Division::quotient ? q : r);
}

// A range of i32 or i64 values, all non-negative.
ConstantIntRanges nonNegative(unsigned width, uint64_t min, uint64_t max) {
  return ConstantIntRanges::fromUnsigned(APInt(width, min), APInt(width, max));
}

} // namespace

#include "idr/IdrInterfaces.cc.inc"

#define GET_OP_CLASSES
#include "idr/IdrOps.cc.inc"

//===----------------------------------------------------------------------===//
// Data declarations (IDR-DATA-*)
//===----------------------------------------------------------------------===//

SmallVector<CtorOp> DataOp::getCtors() {
  return llvm::to_vector(getBody().front().getOps<CtorOp>());
}

Type DataOp::getValueType() {
  auto name = FlatSymbolRefAttr::get(getSymNameAttr());
  if (getBox())
    return BoxType::get(getContext(), name);
  return DataType::get(getContext(), name);
}

// IDR-DATA-1, IDR-DATA-2
LogicalResult DataOp::verify() {
  uint64_t expected = 0;
  for (Operation &op : getBody().front()) {
    auto ctor = dyn_cast<CtorOp>(op);
    if (!ctor)
      return op.emitOpError("is not allowed inside idr.data");
    if (ctor.getTag() != expected)
      return ctor.emitOpError("has tag ")
             << ctor.getTag() << "; tags must be 0..n-1 in order";
    ++expected;
  }
  return success();
}

Type CtorOp::getFieldType(unsigned index) {
  return cast<TypeAttr>(getFieldTypes()[index]).getValue();
}

// IDR-DATA-2, IDR-DATA-3
LogicalResult CtorOp::verify() {
  auto types = getFieldTypes();
  auto quantities = getQuantities();
  if (types.size() != quantities.size())
    return emitOpError("needs one quantity per field");
  for (auto [type, quantityAttr] : llvm::zip(types.getAsValueRange<TypeAttr>(), quantities)) {
    StringRef quantity = cast<StringAttr>(quantityAttr).getValue();
    if (!isFieldType(type))
      return emitOpError("has a field of unsupported type ") << type;
    if (!llvm::is_contained({"0", "1", "w"}, quantity))
      return emitOpError("has quantity '") << quantity << "'";
    if ((quantity == "0") != isa<ErasedType>(type))
      return emitOpError("must use quantity 0 exactly for !idr.erased fields");
  }
  return success();
}

//===----------------------------------------------------------------------===//
// Constants (IDR-CONST-1, IDR-CONST-2)
//===----------------------------------------------------------------------===//

namespace {

// A value without the type that MLIR's parser reads into it (Idr_Attr): the
// form in which values are stored.
Attribute untyped(Attribute value) {
  MLIRContext *ctx = value.getContext();
  return TypeSwitch<Attribute, Attribute>(value)
      .Case([&](ConAttr con) { return ConAttr::get(ctx, con.getCtor(), con.getFields()); })
      .Case([&](ClosureAttr closure) {
        return ClosureAttr::get(ctx, closure.getCallee(), closure.getCaptures());
      })
      .Case([&](BigAttr big) { return BigAttr::get(ctx, big.getValue()); })
      .Case([&](ErasedAttr) { return ErasedAttr::get(ctx); })
      .Case([&](StringAttr str) { return StringAttr::get(ctx, str.getValue()); })
      .Default([](Attribute other) { return other; });
}

} // namespace

// The kinds of value idr.constant holds, stored untyped; scalars are
// arith.constant's.
bool ConstantOp::isBuildableWith(Attribute value, Type type) {
  if (untyped(value) != value)
    return false;
  if (auto con = dyn_cast<ConAttr>(value)) {
    auto name = TypeSwitch<Type, FlatSymbolRefAttr>(type)
                    .Case<DataType, BoxType>([](auto sum) { return sum.getName(); })
                    .Default([](Type) { return nullptr; });
    return name && name.getAttr() == con.getCtor().getRootReference();
  }
  return (isa<ClosureAttr>(value) && isa<FnType>(type)) ||
         (isa<BigAttr>(value) && isa<BigType>(type)) ||
         (isa<ErasedAttr>(value) && isa<ErasedType>(type)) ||
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
  if (!typed || isa<NoneType>(typed.getType()))
    return parser.emitError(loc, "expects a value followed by `:` and its type");
  result.addTypes(typed.getType());
  result.getOrAddProperties<Properties>().value = untyped(value);
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
           << "; it holds constructors, closures, strings, bigs and the erased value, "
              "untyped, and integers and doubles are arith.constant";
  return success();
}

OpFoldResult ConstantOp::fold(FoldAdaptor) { return getValue(); }

namespace {

// That `value` is a constant of `type`, recursively through fields and
// captures, with every symbol resolved.
LogicalResult verifyConstant(Operation *op, SymbolTableCollection &symbols,
                             Attribute value, Type type);

LogicalResult verifyConstants(Operation *op, SymbolTableCollection &symbols,
                              ArrayAttr values, TypeRange types) {
  if (values.size() != types.size())
    return op->emitOpError("has a constant with ")
           << values.size() << " fields or captures where " << types.size()
           << " are expected";
  for (auto [value, type] : llvm::zip(values, types))
    if (failed(verifyConstant(op, symbols, value, type)))
      return failure();
  return success();
}

LogicalResult verifyConstant(Operation *op, SymbolTableCollection &symbols,
                             Attribute value, Type type) {
  if (auto scalar = dyn_cast<TypedAttr>(value);
      scalar && isa<IntegerAttr, FloatAttr>(value) && scalar.getType() == type &&
      isFieldType(type))
    return success();
  if (!ConstantOp::isBuildableWith(value, type))
    return op->emitOpError("has a constant ") << value << " where " << type << " is expected";
  if (auto con = dyn_cast<ConAttr>(value)) {
    auto data = symbols.lookupNearestSymbolFrom<DataOp>(
        op, FlatSymbolRefAttr::get(con.getCtor().getRootReference()));
    if (!data || data.getValueType() != type)
      return op->emitOpError("has a constant of an undeclared type ") << type;
    CtorOp ctor = lookupCtor(data, con.getCtor().getLeafReference());
    if (!ctor)
      return op->emitOpError("has a constant of an unknown constructor ") << con.getCtor();
    SmallVector<Type> fields(ctor.getFieldTypes().getAsValueRange<TypeAttr>());
    return verifyConstants(op, symbols, con.getFields(), fields);
  }
  if (auto closure = dyn_cast<ClosureAttr>(value)) {
    auto fn = symbols.lookupNearestSymbolFrom<func::FuncOp>(op, closure.getCallee());
    if (!fn)
      return op->emitOpError("has a closure of an unknown function ") << closure.getCallee();
    ArrayRef<Type> inputs = fn.getArgumentTypes();
    unsigned captures = closure.getCaptures().size();
    if (captures > inputs.size())
      return op->emitOpError("has a closure with more captures than ")
             << closure.getCallee() << " has parameters";
    auto expected = FnType::get(op->getContext(), inputs.drop_front(captures),
                                fn.getResultTypes());
    if (expected != type)
      return op->emitOpError("has a closure of ")
             << closure.getCallee() << ", of type " << expected << ", where " << type
             << " is expected";
    return verifyConstants(op, symbols, closure.getCaptures(),
                           inputs.take_front(captures));
  }
  return success();
}

} // namespace

LogicalResult ConstantOp::verifySymbolUses(SymbolTableCollection &symbols) {
  return verifyConstant(*this, symbols, getValue(), getType());
}

//===----------------------------------------------------------------------===//
// Constructors, fields and tags (IDR-CON-1, IDR-FIELD-1, IDR-TAG-1)
//===----------------------------------------------------------------------===//

// A box's constructor allocates its cell, so CSE never merges two of them;
// an unused one is still dead code (wouldOpBeTriviallyDead).
void ConOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  if (isa<BoxType>(getType()))
    effects.emplace_back(MemoryEffects::Allocate::get(), getOperation()->getOpResult(0),
                         SideEffects::DefaultResource::get());
}

Speculation::Speculatability ConOp::getSpeculatability() {
  return isa<BoxType>(getType()) ? Speculation::NotSpeculatable
                                 : Speculation::Speculatable;
}

LogicalResult ConOp::verifySymbolUses(SymbolTableCollection &symbols) {
  SymbolRefAttr ref = getCtor();
  if (ref.getNestedReferences().size() != 1)
    return emitOpError("expects a constructor reference @T::@C");
  auto data = symbols.lookupNearestSymbolFrom<DataOp>(
      *this, FlatSymbolRefAttr::get(ref.getRootReference()));
  CtorOp ctor = lookupCtor(data, ref.getLeafReference());
  if (!ctor)
    return emitOpError("refers to an unknown constructor ") << ref;
  if (data.getValueType() != getType())
    return emitOpError("builds ") << ref << " but has type " << getType();
  auto types = ctor.getFieldTypes();
  if (types.size() != getFields().size())
    return emitOpError("expects ") << types.size() << " fields";
  for (auto [expected, value] : llvm::zip(types.getAsValueRange<TypeAttr>(), getFields()))
    if (expected != value.getType())
      return emitOpError("field has type ") << value.getType() << ", expected " << expected;
  return success();
}

OpFoldResult ConOp::fold(FoldAdaptor adaptor) {
  if (llvm::is_contained(adaptor.getFields(), Attribute()))
    return {};
  return ConAttr::get(getContext(), getCtor(), ArrayAttr::get(getContext(), adaptor.getFields()));
}

LogicalResult FieldOp::verifySymbolUses(SymbolTableCollection &symbols) {
  auto data = symbols.lookupNearestSymbolFrom<DataOp>(
      *this, isa<DataType>(getValue().getType()) ? cast<DataType>(getValue().getType()).getName()
                                                 : cast<BoxType>(getValue().getType()).getName());
  CtorOp ctor = lookupCtor(data, getCtor());
  if (!ctor)
    return emitOpError("refers to an unknown constructor ") << getCtorAttr();
  if (getIndex() >= ctor.getFieldTypes().size())
    return emitOpError("field index out of range");
  if (ctor.getFieldType(static_cast<unsigned>(getIndex())) != getType())
    return emitOpError("result type does not match the field type");
  return success();
}

// A field of a known constructor, built by idr.con or constant.
OpFoldResult FieldOp::fold(FoldAdaptor adaptor) {
  auto index = static_cast<unsigned>(getIndex());
  if (auto con = getValue().getDefiningOp<ConOp>())
    if (con.getCtor().getLeafReference() == getCtorAttr().getAttr())
      return con.getFields()[index];
  if (auto con = dyn_cast_or_null<ConAttr>(adaptor.getValue()))
    if (con.getCtor().getLeafReference() == getCtorAttr().getAttr())
      return con.getFields()[index];
  return {};
}

// The tag of a known constructor, or 0 for a type of one constructor.
OpFoldResult TagOp::fold(FoldAdaptor adaptor) {
  auto tag = [&](CtorOp ctor) -> OpFoldResult {
    if (!ctor)
      return {};
    return IntegerAttr::get(getType(), ctor.getTag());
  };
  if (auto con = getValue().getDefiningOp<ConOp>())
    return tag(lookupCtor(*this, con.getCtor()));
  if (auto con = dyn_cast_or_null<ConAttr>(adaptor.getValue()))
    return tag(lookupCtor(*this, con.getCtor()));
  if (DataOp data = lookupData(*this, getValue().getType()))
    if (data.getCtors().size() == 1)
      return tag(data.getCtors().front());
  return {};
}

// IDR-RANGE-1
void TagOp::inferResultRanges(ArrayRef<ConstantIntRanges>, SetIntRangeFn setResultRange) {
  DataOp data = lookupData(*this, getValue().getType());
  size_t count = data ? data.getCtors().size() : 0;
  setResultRange(getResult(), count == 0 ? ConstantIntRanges::maxRange(64)
                                         : nonNegative(64, 0, count - 1));
}

//===----------------------------------------------------------------------===//
// Matches (IDR-MATCH-5, IDR-MATCH-6)
//===----------------------------------------------------------------------===//

namespace {

// Parses `{ case <key> <region> ... default <region> }`; `parseCase` parses
// a key and its region.
ParseResult parseMatchBody(OpAsmParser &parser, OperationState &result,
                           function_ref<ParseResult(Region &)> parseCase) {
  if (parser.parseLBrace())
    return failure();
  while (succeeded(parser.parseOptionalKeyword("case")))
    if (parseCase(*result.addRegion()))
      return failure();
  if (succeeded(parser.parseOptionalKeyword("default")) &&
      parser.parseRegion(*result.addRegion()))
    return failure();
  return parser.parseRBrace();
}

// `%v : T -> (R...) attributes {...}`, the part both matches share.
ParseResult parseMatchHead(OpAsmParser &parser, OperationState &result, Type &scrutineeType) {
  OpAsmParser::UnresolvedOperand scrutinee;
  SmallVector<Type> resultTypes;
  if (parser.parseOperand(scrutinee) || parser.parseColonType(scrutineeType) ||
      parser.parseArrow() ||
      parser.parseCommaSeparatedList(OpAsmParser::Delimiter::Paren,
                                     [&] { return parser.parseType(resultTypes.emplace_back()); }) ||
      parser.resolveOperand(scrutinee, scrutineeType, result.operands) ||
      parser.parseOptionalAttrDictWithKeyword(result.attributes))
    return failure();
  result.addTypes(resultTypes);
  return success();
}

template <typename Match>
void printMatch(Match op, OpAsmPrinter &printer, function_ref<void(unsigned)> printKey) {
  printer << ' ' << op.getScrutinee() << " : " << op.getScrutinee().getType() << " -> (";
  llvm::interleaveComma(op.getResultTypes(), printer);
  printer << ')';
  printer.printOptionalAttrDictWithKeyword(op->getAttrs(), {"cases"});
  printer << " {";
  for (unsigned i = 0, e = op.getCases().size(); i < e; ++i) {
    printer.printNewline();
    printer << "case ";
    printKey(i);
    printer << ' ';
    printer.printRegion(op.getCaseRegion(i), /*printEntryBlockArgs=*/false);
  }
  if (Region *fallback = op.getDefaultRegion()) {
    printer.printNewline();
    printer << "default ";
    printer.printRegion(*fallback);
  }
  printer.printNewline();
  printer << '}';
}

// Every region ends in idr.yield with the match's result types, or in
// ub.unreachable after a crash.
LogicalResult verifyMatchRegions(Operation *op) {
  for (auto [index, region] : llvm::enumerate(op->getRegions())) {
    Block &block = region.front();
    if (block.empty())
      return op->emitOpError("region #") << index << " is empty";
    Operation *terminator = &block.back();
    if (isa<ub::UnreachableOp>(terminator))
      continue;
    auto yield = dyn_cast<YieldOp>(terminator);
    if (!yield)
      return op->emitOpError("region #")
             << index << " must end in idr.yield or ub.unreachable";
    if (yield.getResults().getTypes() != op->getResultTypes())
      return yield.emitOpError("yields ")
             << yield.getResults().getTypes() << " but the match has results "
             << op->getResultTypes();
  }
  return success();
}

// The region of `Match` taken for the key `key`: its case, else the default.
template <typename Match>
Region *takenRegion(Match op, Attribute key) {
  const auto *it = llvm::find(op.getCases(), key);
  if (it != op.getCases().end())
    return &op.getCaseRegion(static_cast<unsigned>(it - op.getCases().begin()));
  return op.getDefaultRegion();
}

} // namespace

// `idr.match %v : T -> (R...) { case @C(%x: A) {...} ... default {...} }`
ParseResult MatchOp::parse(OpAsmParser &parser, OperationState &result) {
  Type scrutineeType;
  SmallVector<Attribute> cases;
  if (parseMatchHead(parser, result, scrutineeType) ||
      parseMatchBody(parser, result, [&](Region &region) -> ParseResult {
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
  printMatch(*this, printer, [&](unsigned index) {
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
  if (Region *fallback = getDefaultRegion(); fallback && fallback->getNumArguments())
    return emitOpError("expects a default region without arguments");
  return verifyMatchRegions(*this);
}

// Each case is a constructor of the scrutinee's type, and its region's
// arguments are that constructor's fields.
LogicalResult MatchOp::verifySymbolUses(SymbolTableCollection &) {
  DataOp data = lookupData(*this, getScrutinee().getType());
  for (auto [index, name] : llvm::enumerate(getCases().getAsRange<FlatSymbolRefAttr>())) {
    CtorOp ctor = lookupCtor(data, name.getValue());
    if (!ctor)
      return emitOpError("has a case for ")
             << name << ", which is not a constructor of " << getScrutinee().getType();
    TypeRange args = getCaseRegion(static_cast<unsigned>(index)).getArgumentTypes();
    if (!llvm::equal(args, ctor.getFieldTypes().getAsValueRange<TypeAttr>()))
      return emitOpError("case ") << name << " must take the constructor's fields "
                                  << ctor.getFieldTypes();
  }
  return success();
}

// A constant constructor, or the constructor of the idr.con that built the
// scrutinee.
Region *MatchOp::getTakenRegion(Attribute value) {
  SymbolRefAttr ctor;
  if (auto con = dyn_cast_or_null<ConAttr>(value))
    ctor = con.getCtor();
  else if (auto con = getScrutinee().getDefiningOp<ConOp>())
    ctor = con.getCtor();
  if (!ctor)
    return nullptr;
  return takenRegion(*this, FlatSymbolRefAttr::get(ctor.getLeafReference()));
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
    if (!isa<BigType>(type))
      return parser.emitError(parser.getCurrentLocation(), "a literal match on ")
             << type << " has no keys";
    BigAttr big;
    if (parser.parseAttribute(big))
      return failure();
    return Attribute(big);
  };
  if (parseMatchHead(parser, result, type) ||
      parseMatchBody(parser, result, [&](Region &region) -> ParseResult {
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
  printMatch(*this, printer,
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
                     .Default([](Type) { return false; });
    if (!typed)
      return emitOpError("has a key ") << key << " that is not a literal of " << type;
    if (!seen.insert(key).second)
      return emitOpError("has two cases for ") << key;
  }
  for (Region &region : getRegions())
    if (region.getNumArguments())
      return emitOpError("expects regions without arguments");
  return verifyMatchRegions(*this);
}

Region *MatchLitOp::getTakenRegion(Attribute value) {
  if (!value)
    return nullptr;
  return takenRegion(*this, value);
}

// RegionBranchOpInterface, as scf.index_switch: control enters exactly one
// region, which returns to the match.
namespace {

void matchSuccessors(Operation *op, RegionBranchPoint point,
                     SmallVectorImpl<RegionSuccessor> &successors) {
  if (!point.isParent()) {
    successors.push_back(RegionSuccessor(op));
    return;
  }
  for (Region &region : op->getRegions())
    successors.emplace_back(&region);
}

void matchEntrySuccessors(Operation *op, Region *taken,
                          SmallVectorImpl<RegionSuccessor> &successors) {
  if (taken)
    successors.emplace_back(taken);
  else
    matchSuccessors(op, RegionBranchPoint::parent(), successors);
}

void matchInvocationBounds(Operation *op, Region *taken,
                           SmallVectorImpl<InvocationBounds> &bounds) {
  for (Region &region : op->getRegions())
    bounds.emplace_back(/*lb=*/0, /*ub=*/!taken || taken == &region ? 1 : 0);
}

} // namespace

void MatchOp::getSuccessorRegions(RegionBranchPoint point,
                                  SmallVectorImpl<RegionSuccessor> &successors) {
  matchSuccessors(*this, point, successors);
}

void MatchOp::getEntrySuccessorRegions(ArrayRef<Attribute> operands,
                                       SmallVectorImpl<RegionSuccessor> &successors) {
  matchEntrySuccessors(*this, getTakenRegion(operands.front()), successors);
}

void MatchOp::getRegionInvocationBounds(ArrayRef<Attribute> operands,
                                        SmallVectorImpl<InvocationBounds> &bounds) {
  matchInvocationBounds(*this, getTakenRegion(operands.front()), bounds);
}

ValueRange MatchOp::getSuccessorInputs(RegionSuccessor successor) {
  return successor.isOperation() ? ValueRange(getResults()) : ValueRange();
}

void MatchLitOp::getSuccessorRegions(RegionBranchPoint point,
                                     SmallVectorImpl<RegionSuccessor> &successors) {
  matchSuccessors(*this, point, successors);
}

void MatchLitOp::getEntrySuccessorRegions(ArrayRef<Attribute> operands,
                                          SmallVectorImpl<RegionSuccessor> &successors) {
  matchEntrySuccessors(*this, getTakenRegion(operands.front()), successors);
}

void MatchLitOp::getRegionInvocationBounds(ArrayRef<Attribute> operands,
                                           SmallVectorImpl<InvocationBounds> &bounds) {
  matchInvocationBounds(*this, getTakenRegion(operands.front()), bounds);
}

ValueRange MatchLitOp::getSuccessorInputs(RegionSuccessor successor) {
  return successor.isOperation() ? ValueRange(getResults()) : ValueRange();
}

//===----------------------------------------------------------------------===//
// Closures (IDR-CLOS-1)
//===----------------------------------------------------------------------===//

// A8: worlds pass only as arguments and results, never in a closure.
LogicalResult ClosureOp::verify() {
  if (llvm::any_of(getCaptures().getTypes(), llvm::IsaPred<WorldType>))
    return emitOpError("captures a world; a world passes only as an argument or "
                       "result (IDR-WORLD-1)");
  return success();
}

// The callee's leading parameters are the captures, and the rest of its
// signature is the closure's type.
LogicalResult ClosureOp::verifySymbolUses(SymbolTableCollection &symbols) {
  auto fn = symbols.lookupNearestSymbolFrom<func::FuncOp>(*this, getCalleeAttr());
  if (!fn)
    return emitOpError("refers to an unknown function ") << getCalleeAttr();
  ArrayRef<Type> inputs = fn.getArgumentTypes();
  size_t captures = getCaptures().size();
  if (captures > inputs.size() ||
      !llvm::equal(getCaptures().getTypes(), inputs.take_front(captures)))
    return emitOpError("captures ")
           << getCaptures().getTypes() << ", which are not the leading parameters of "
           << getCalleeAttr();
  auto expected = FnType::get(getContext(), inputs.drop_front(captures), fn.getResultTypes());
  if (expected != getType())
    return emitOpError("has type ") << getType() << ", but a closure of " << getCalleeAttr()
                                    << " with these captures is " << expected;
  return success();
}

OpFoldResult ClosureOp::fold(FoldAdaptor adaptor) {
  if (llvm::is_contained(adaptor.getCaptures(), Attribute()))
    return {};
  return ClosureAttr::get(getContext(), getCalleeAttr(),
                          ArrayAttr::get(getContext(), adaptor.getCaptures()));
}

//===----------------------------------------------------------------------===//
// Crashes (IDR-CRASH-1)
//===----------------------------------------------------------------------===//

std::optional<StringRef> CrashOp::getCrashCause() { return getMessage(); }

//===----------------------------------------------------------------------===//
// Scalars (IDR-CHAR-1, IDR-DBL-*)
//===----------------------------------------------------------------------===//

OpFoldResult ToCharOp::fold(FoldAdaptor adaptor) {
  auto value = dyn_cast_or_null<IntegerAttr>(adaptor.getValue());
  if (!value)
    return {};
  const APInt &bits = value.getValue();
  bool negative = getIsSigned() && bits.isNegative();
  uint64_t code = negative || bits.getActiveBits() > 32 ? UINT64_MAX
                                                        : bits.getZExtValue();
  bool scalar = code <= 0xD7FF || (code >= 0xE000 && code <= 0x10FFFF);
  return IntegerAttr::get(getType(), scalar ? static_cast<int64_t>(code) : 0);
}

void ToCharOp::inferResultRanges(ArrayRef<ConstantIntRanges>, SetIntRangeFn setResultRange) {
  setResultRange(getResult(), nonNegative(32, 0, 0x10FFFF));
}

OpFoldResult ToIntOp::fold(FoldAdaptor adaptor) {
  auto value = dyn_cast_or_null<FloatAttr>(adaptor.getValue());
  if (!value || !value.getValue().isFinite())
    return {};
  // Truncated exactly, then wrapped: 1100 bits hold any finite double.
  APSInt whole(1100, /*isUnsigned=*/false);
  bool exact = false;
  value.getValue().convertToInteger(whole, APFloat::rmTowardZero, &exact);
  return IntegerAttr::get(getType(), whole.trunc(getType().getIntOrFloatBitWidth()));
}

std::optional<StringRef> ToIntOp::getCrashCause() {
  if (knownFinite(getValue()))
    return std::nullopt;
  return StringRef("cast of a non-finite Double");
}

// '+' (NaN and positive infinity), '-', or a digit.
void DoubleHeadOp::inferResultRanges(ArrayRef<ConstantIntRanges>,
                                     SetIntRangeFn setResultRange) {
  setResultRange(getResult(), nonNegative(32, '+', '9'));
}

// '-' or a digit; a digit when unsigned.
void IntHeadOp::inferResultRanges(ArrayRef<ConstantIntRanges>, SetIntRangeFn setResultRange) {
  setResultRange(getResult(), nonNegative(32, getIsSigned() ? '-' : '0', '9'));
}

//===----------------------------------------------------------------------===//
// Strings (IDR-STR-2)
//===----------------------------------------------------------------------===//

LogicalResult StrShowOp::verify() {
  if (isa<FloatType>(getValue().getType()) && getIsSigned())
    return emitOpError("shows a Double, which has no signedness");
  return success();
}

void StrLengthOp::inferResultRanges(ArrayRef<ConstantIntRanges>, SetIntRangeFn setResultRange) {
  setResultRange(getResult(), nonNegative(64, 0, INT64_MAX));
}

// In range when both operands are constants and the index is below the
// number of characters (UTF-8 lead bytes).
std::optional<StringRef> StrIndexOp::getCrashCause() {
  StringAttr str;
  APInt index;
  if (matchPattern(getStr(), m_Constant(&str)) && matchPattern(getIndex(), m_ConstantInt(&index))) {
    auto characters = static_cast<uint64_t>(
        llvm::count_if(str.getValue(), [](char c) { return (c & 0xC0) != 0x80; }));
    if (!index.isNegative() && index.getZExtValue() < characters)
      return std::nullopt;
  }
  return StringRef("string index out of range");
}
