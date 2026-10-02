// The idr ops: syntax, verifiers, folders and interfaces.

#include "Dialect/BigRanges.h"
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
// Facts that rule out a crash
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

// `: !idr.nat` on a big op that computes on naturals; nothing on one that
// computes on Integers, which most do.
// A result type written only when it is not the plain type the op has by
// default (a big, a string, a natural): `: !idr.nat`, `: !idr.own<!idr.str>`.
ParseResult parseResultAtGrade(OpAsmParser &parser, Type &type, Type plain) {
  if (succeeded(parser.parseOptionalColon()))
    return parser.parseType(type);
  type = plain;
  return success();
}

void printResultAtGrade(OpAsmPrinter &printer, Type type, Type plain) {
  if (type != plain)
    printer << ": " << type;
}

ParseResult parseNatural(OpAsmParser &parser, Type &type) {
  return parseResultAtGrade(parser, type, BigType::get(parser.getContext()));
}

void printNatural(OpAsmPrinter &printer, Operation *, Type type) {
  printResultAtGrade(printer, type, BigType::get(type.getContext()));
}

// A parenthesized list of result types, which may be empty: `()`.
ParseResult parseResultTypes(OpAsmParser &parser, SmallVectorImpl<Type> &types) {
  if (parser.parseLParen())
    return failure();
  if (succeeded(parser.parseOptionalRParen()))
    return success();
  return failure(parser.parseTypeList(types) || parser.parseRParen());
}

void printResultTypes(OpAsmPrinter &printer, Operation *, TypeRange types) {
  printer << '(';
  llvm::interleaveComma(types, printer);
  printer << ')';
}

// The result of a dup: the value owned, unless written, `-> T`, at another
// owned grade.
ParseResult parseOwnedResult(OpAsmParser &parser, Type &type, Type value) {
  if (succeeded(parser.parseOptionalArrow()))
    return parser.parseType(type);
  type = owned(value);
  return success();
}

void printOwnedResult(OpAsmPrinter &printer, Operation *, Type type, Type value) {
  if (type != owned(value))
    printer << " -> " << type;
}

// The result of an op on naturals or bigs: its operands' type unless
// written, `-> T`, at another grade.
ParseResult parseNaturalResult(OpAsmParser &parser, Type &type, Type operand) {
  if (succeeded(parser.parseOptionalArrow()))
    return parser.parseType(type);
  type = operand;
  return success();
}

void printNaturalResult(OpAsmPrinter &printer, Operation *, Type type, Type operand) {
  if (type != operand)
    printer << "-> " << type;
}

ParseResult parseStrResult(OpAsmParser &parser, Type &type) {
  return parseResultAtGrade(parser, type, StrType::get(parser.getContext()));
}

void printStrResult(OpAsmPrinter &printer, Operation *, Type type) {
  printResultAtGrade(printer, type, StrType::get(type.getContext()));
}

ParseResult parseBigResult(OpAsmParser &parser, Type &type) {
  return parseResultAtGrade(parser, type, BigType::get(parser.getContext()));
}

void printBigResult(OpAsmPrinter &printer, Operation *, Type type) {
  printResultAtGrade(printer, type, BigType::get(type.getContext()));
}

ParseResult parseNatResult(OpAsmParser &parser, Type &type) {
  return parseResultAtGrade(parser, type, NatType::get(parser.getContext()));
}

void printNatResult(OpAsmPrinter &printer, Operation *, Type type) {
  printResultAtGrade(printer, type, NatType::get(type.getContext()));
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
// Division, shared by idr.div and idr.mod through IdrOps.td
//===----------------------------------------------------------------------===//

// Euclidean quotient and remainder on the mathematical values of
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
// Data declarations
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

LogicalResult DataOp::verify() {
  for (Operation &op : getBody().front())
    if (!isa<CtorOp>(op))
      return op.emitOpError("is not allowed inside idr.data");
  return success();
}

Type CtorOp::getFieldType(unsigned index) {
  return cast<TypeAttr>(getFieldTypes()[index]).getValue();
}

unsigned CtorOp::getTag() {
  Block *body = (*this)->getBlock();
  return static_cast<unsigned>(std::distance(body->begin(), (*this)->getIterator()));
}

LogicalResult CtorOp::verify() {
  for (Type type : getFieldTypes().getAsValueRange<TypeAttr>())
    if (!isFieldType(type))
      return emitOpError("has a field of unsupported type ") << type;
  return success();
}

//===----------------------------------------------------------------------===//
// Constants
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
           << "; it holds constructors, closures, strings, bigs, naturals that are not "
              "negative and the erased value, "
              "untyped, and integers and doubles are arith.constant";
  return success();
}

OpFoldResult ConstantOp::fold(FoldAdaptor) { return getValue(); }

namespace {

// The constants and types already checked: a constant that compile-time
// evaluation made shares its parts, and each is checked once.
using Checked = llvm::DenseSet<std::pair<Attribute, Type>>;

// That `value` is a constant of `type`, recursively through fields and
// captures, with every symbol resolved.
LogicalResult verifyConstant(Operation *op, SymbolTableCollection &symbols,
                             Attribute value, Type type, Checked &checked);

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

LogicalResult verifyConstant(Operation *op, SymbolTableCollection &symbols,
                             Attribute value, Type type, Checked &checked) {
  if (!checked.insert({value, type}).second)
    return success();
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
    return verifyConstants(op, symbols, con.getFields(), fields, checked);
  }
  if (auto closure = dyn_cast<ClosureAttr>(value)) {
    auto fn = symbols.lookupNearestSymbolFrom<func::FuncOp>(op, closure.getCallee());
    if (!fn)
      return op->emitOpError("has a closure of an unknown function ") << closure.getCallee();
    ArrayRef<Type> inputs = fn.getArgumentTypes();
    size_t captures = closure.getCaptures().size();
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
                           inputs.take_front(captures), checked);
  }
  return success();
}

} // namespace

LogicalResult ConstantOp::verifySymbolUses(SymbolTableCollection &symbols) {
  Checked checked;
  return verifyConstant(*this, symbols, getValue(), getType(), checked);
}

//===----------------------------------------------------------------------===//
// Constructors, fields and tags
//===----------------------------------------------------------------------===//

// A box's constructor allocates its cell, so CSE never merges two of them;
// an unused one is still dead code (wouldOpBeTriviallyDead). A cell
// idr-stack keeps in its frame (`idr.stack`) is stack memory, the resource
// MLIR's allocas use.
void ConOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  if (!isa<BoxType>(unrestricted(getType())))
    return;
  SideEffects::DefaultResource *memory =
      (*this)->hasAttr("idr.stack") ? SideEffects::AutomaticAllocationScopeResource::get()
                                    : SideEffects::DefaultResource::get();
  effects.emplace_back(MemoryEffects::Allocate::get(), getOperation()->getOpResult(0), memory);
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
  if (data.getValueType() != unrestricted(getType()))
    return emitOpError("builds ") << ref << " but has type " << getType();
  auto types = ctor.getFieldTypes();
  if (types.size() != getFields().size())
    return emitOpError("expects ") << types.size() << " fields";
  // In the owned stage a field that holds references is owned (or
  // exclusive): it moves into the cell.
  for (auto [expected, value] : llvm::zip(types.getAsValueRange<TypeAttr>(), getFields()))
    if (expected != value.getType() && !(isOwned(value.getType()) && view(value.getType()) == expected))
      return emitOpError("field has type ") << value.getType() << ", expected " << expected;
  return success();
}

LogicalResult FieldOp::verifySymbolUses(SymbolTableCollection &symbols) {
  auto data =
      symbols.lookupNearestSymbolFrom<DataOp>(*this, getSumName(getValue().getType()));
  CtorOp ctor = lookupCtor(data, getCtor());
  if (!ctor)
    return emitOpError("refers to an unknown constructor ") << getCtorAttr();
  if (getIndex() >= ctor.getFieldTypes().size())
    return emitOpError("field index out of range");
  // A field is read at the value's grade times its own, as a match binds it.
  Type expected = fieldType(getValue().getType(), ctor.getFieldType(static_cast<unsigned>(getIndex())));
  if (expected != getType())
    return emitOpError("has result ") << getType() << ", but the field of a "
                                      << getValue().getType() << " is read as " << expected;
  return success();
}

// A field of a known constructor, built by idr.con or constant, also when
// it passed a linear position on the way. A linear field moves out of the
// constructor, so only the constructor's one read takes it: otherwise it
// would be used twice.
OpFoldResult FieldOp::fold(FoldAdaptor adaptor) {
  auto index = static_cast<unsigned>(getIndex());
  Value source = throughLinear(getValue());
  if (auto con = source.getDefiningOp<ConOp>())
    if (con.getCtor().getLeafReference() == getCtorAttr().getAttr()) {
      // A field read at another grade than the constructor took it is
      // the canonicalizer's, which holds it as read.
      Value field = con.getFields()[index];
      if (field.getType() == getType() &&
          (quantityOf(field.getType()) != Quantity::One || fieldReadOnce(con.getResult(), index)))
        return field;
    }
  // The constant is the operand's, as folding or constant propagation knows
  // it, or the one it passed a linear position from.
  auto con = dyn_cast_or_null<ConAttr>(adaptor.getValue());
  if (!con)
    matchPattern(source, m_Constant(&con));
  if (con && con.getCtor().getLeafReference() == getCtorAttr().getAttr())
    return con.getFields()[index];
  return {};
}

// The value an entry used at once held, and the linear value a use entered
// at once was.
OpFoldResult LinUseOp::fold(FoldAdaptor) {
  if (auto enter = getLinear().getDefiningOp<LinEnterOp>())
    return enter.getValue();
  return {};
}

// Only when the entry is the use's one reader: a match that read the used
// value and a region that enters it again would otherwise both use the
// linear value on one path.
OpFoldResult LinEnterOp::fold(FoldAdaptor) {
  if (auto use = getValue().getDefiningOp<LinUseOp>())
    if (use.getResult().hasOneUse())
      return use.getLinear();
  return {};
}

// A linear value has the range of the value that entered it. MLIR's range
// analysis has no range for a value whose type is not an integer, so the
// linear value a parameter or a region binds has none; its use then has
// every value of its type, where an entry's use waits for the entry's.
namespace {

// The range of any value of `type`, whose grade is no part of it: an
// integer's full width, a big's no bound, a natural's at least 0; none for a
// type without integers.
std::optional<IntegerValueRange> anyValue(Type type) {
  type = unrestricted(type);
  if (isa<BigType, NatType>(type))
    return IntegerValueRange(
        ranges::rangeOf(isa<NatType>(type) ? ranges::natural() : ranges::Bounds{}));
  if (type.isIntOrIndex())
    return IntegerValueRange(ConstantIntRanges::maxRange(
        type.isIndex() ? IndexType::kInternalStorageBitWidth : type.getIntOrFloatBitWidth()));
  return std::nullopt;
}

// A linear value's range is its value's, which the grade must not hide. A
// linear value the analysis never saw computed (a field a match binds)
// starts at a range of the linear type, which states no width; it stands
// for any value.
void passRange(Value result, const IntegerValueRange &range, SetIntLatticeFn setResultRange) {
  std::optional<IntegerValueRange> any = anyValue(result.getType());
  if (!any)
    return;
  if (!range.isUninitialized() &&
      range.getValue().umin().getBitWidth() == any->getValue().umin().getBitWidth())
    setResultRange(result, range);
  else
    setResultRange(result, *any);
}

} // namespace

void LinEnterOp::inferResultRangesFromOptional(ArrayRef<IntegerValueRange> ranges,
                                               SetIntLatticeFn setResultRange) {
  if (!ranges.front().isUninitialized())
    passRange(getResult(), ranges.front(), setResultRange);
}

void LinUseOp::inferResultRangesFromOptional(ArrayRef<IntegerValueRange> ranges,
                                             SetIntLatticeFn setResultRange) {
  if (ranges.front().isUninitialized() && getLinear().getDefiningOp<LinEnterOp>())
    return;
  passRange(getResult(), ranges.front(), setResultRange);
}

// The tag of a known constructor, or 0 for a type of one constructor.
OpFoldResult TagOp::fold(FoldAdaptor adaptor) {
  auto tag = [&](CtorOp ctor) -> OpFoldResult {
    if (!ctor)
      return {};
    return IntegerAttr::get(getType(), static_cast<int64_t>(ctor.getTag()));
  };
  Value source = throughLinear(getValue());
  if (auto con = source.getDefiningOp<ConOp>())
    return tag(lookupCtor(*this, con.getCtor()));
  auto con = dyn_cast_or_null<ConAttr>(adaptor.getValue());
  if (con || matchPattern(source, m_Constant(&con)))
    return tag(lookupCtor(*this, con.getCtor()));
  if (DataOp data = lookupData(*this, getValue().getType()))
    if (data.getCtors().size() == 1)
      return tag(data.getCtors().front());
  return {};
}

void TagOp::inferResultRanges(ArrayRef<ConstantIntRanges>, SetIntRangeFn setResultRange) {
  DataOp data = lookupData(*this, getValue().getType());
  size_t count = data ? data.getCtors().size() : 0;
  unsigned width = getType().getIntOrFloatBitWidth();
  setResultRange(getResult(), count == 0 ? ConstantIntRanges::maxRange(width)
                                         : nonNegative(width, 0, count - 1));
}

//===----------------------------------------------------------------------===//
// Matches
//===----------------------------------------------------------------------===//

namespace {

// Parses `{ case <key> <region> ... default[(<args>)] <region> }`;
// `parseCase` parses a key and its region.
ParseResult parseMatchBody(OpAsmParser &parser, OperationState &result,
                           function_ref<ParseResult(Region &)> parseCase) {
  if (parser.parseLBrace())
    return failure();
  while (succeeded(parser.parseOptionalKeyword("case")))
    if (parseCase(*result.addRegion()))
      return failure();
  if (succeeded(parser.parseOptionalKeyword("default"))) {
    SmallVector<OpAsmParser::Argument> args;
    if (parser.parseArgumentList(args, OpAsmParser::Delimiter::OptionalParen,
                                 /*allowType=*/true) ||
        parser.parseRegion(*result.addRegion(), args))
      return failure();
  }
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
  for (unsigned i = 0, e = static_cast<unsigned>(op.getCases().size()); i < e; ++i) {
    printer.printNewline();
    printer << "case ";
    printKey(i);
    printer << ' ';
    printer.printRegion(op.getCaseRegion(i), /*printEntryBlockArgs=*/false);
  }
  if (Region *fallback = op.getDefaultRegion()) {
    printer.printNewline();
    printer << "default";
    if (fallback->getNumArguments() != 0) {
      printer << '(';
      llvm::interleaveComma(fallback->getArguments(), printer,
                            [&](BlockArgument arg) { printer.printRegionArgument(arg); });
      printer << ')';
    }
    printer << ' ';
    printer.printRegion(*fallback, /*printEntryBlockArgs=*/false);
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
  if (Region *fallback = getDefaultRegion()) {
    TypeRange args = fallback->getArgumentTypes();
    if (args.size() > 1 || (args.size() == 1 && args.front() != getScrutinee().getType()))
      return emitOpError("expects a default region without arguments, or one that takes the "
                         "scrutinee back at its type");
  }
  return verifyMatchRegions(*this);
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
// scrutinee, also through a linear position.
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
    if (!isa<BigType, NatType>(type))
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
// Closures
//===----------------------------------------------------------------------===//

// Worlds pass only as arguments and results, never
// in a closure.
LogicalResult ClosureOp::verify() {
  if (llvm::any_of(getCaptures().getTypes(), isWorld))
    return emitOpError("captures a world; a world passes only as an argument or result");
  // A closure holding a linear value is used once as well: applied where
  // it is made, or entered into a linear type, whose one use the linearity
  // check then follows. Any other use could apply it twice.
  if (llvm::none_of(getCaptures().getTypes(),
                    [](Type type) { return quantityOf(type) == Quantity::One; }))
    return success();
  if (getResult().use_empty())
    return success();
  OpOperand &use = *getResult().getUses().begin();
  auto apply = dyn_cast<ApplyOp>(use.getOwner());
  bool linear = getResult().hasOneUse() &&
                (isa<LinEnterOp>(use.getOwner()) || (apply && apply.getCallee() == getResult()));
  if (!linear)
    return emitOpError("captures a linear value, so its one use must apply it or enter it "
                       "into a linear type");
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
// Crashes
//===----------------------------------------------------------------------===//

std::optional<StringRef> CrashOp::getCrashCause() { return getMessage(); }

//===----------------------------------------------------------------------===//
// Scalars
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

// A constant that is a byte: 0 to 255.
bool isByte(Attribute constant) {
  auto value = dyn_cast_or_null<IntegerAttr>(constant);
  return value && !value.getValue().isNegative() && value.getValue().isIntN(8);
}

OpFoldResult ToByteOp::fold(FoldAdaptor adaptor) {
  if (!isByte(adaptor.getValue()))
    return {};
  return IntegerAttr::get(getType(), cast<IntegerAttr>(adaptor.getValue()).getValue().trunc(8));
}

std::optional<StringRef> ToByteOp::getCrashCause() {
  Attribute constant;
  if (matchPattern(getValue(), m_Constant(&constant)) && isByte(constant))
    return std::nullopt;
  return StringRef("a byte outside 0 to 255");
}

void ToByteOp::inferResultRanges(ArrayRef<ConstantIntRanges>, SetIntRangeFn setResultRange) {
  setResultRange(getResult(), nonNegative(8, 0, 255));
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
// Strings
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

//===----------------------------------------------------------------------===//
// Destinations
//===----------------------------------------------------------------------===//

LogicalResult DestOfOp::verifySymbolUses(SymbolTableCollection &symbols) {
  auto data =
      symbols.lookupNearestSymbolFrom<DataOp>(*this, getSumName(getValue().getType()));
  CtorOp ctor = lookupCtor(data, getCtor());
  if (!ctor)
    return emitOpError("refers to an unknown constructor ") << getCtorAttr();
  if (getIndex() >= ctor.getFieldTypes().size())
    return emitOpError("field index out of range");
  // A destination is the field's word, whatever grade the field is held at.
  if (unrestricted(ctor.getFieldType(static_cast<unsigned>(getIndex()))) != getType().getValue())
    return emitOpError("destination type does not match the field type");
  return success();
}

// The cell was built here, by an idr.con or idr.reuse of the constructor,
// with the field pending: a destination names a field that has no value
// yet, and nothing else does. In the owned stage the cell is owned and
// the destination reads it through a view.
LogicalResult DestOfOp::verify() {
  Value cell = getValue();
  if (auto borrow = cell.getDefiningOp<BorrowOp>())
    cell = borrow.getValue();
  Operation *made = cell.getDefiningOp();
  ValueRange fields;
  SymbolRefAttr ctor;
  if (auto con = dyn_cast_or_null<ConOp>(made)) {
    fields = con.getFields();
    ctor = con.getCtor();
  } else if (auto reuse = dyn_cast_or_null<ReuseOp>(made)) {
    fields = reuse.getFields();
    ctor = reuse.getCtor();
  } else {
    return emitOpError("expects the cell of an idr.con or idr.reuse");
  }
  auto index = static_cast<unsigned>(getIndex());
  if (ctor.getLeafReference() != getCtorAttr().getAttr())
    return emitOpError("names a field of ") << getCtorAttr() << ", which did not build the cell";
  if (index >= fields.size() || !fields[index].getDefiningOp<PendingOp>())
    return emitOpError("names a field the cell was built with");
  return success();
}

//===----------------------------------------------------------------------===//
// Arrays
//===----------------------------------------------------------------------===//

namespace {

// An element moves into an array, or out of it, at the element type at any
// grade: plain before idr-rc, and owned after it when it holds references.
LogicalResult verifyElement(Operation *op, StringRef what, Type type, MemRefType array) {
  if (view(type) != array.getElementType())
    return op->emitOpError() << what << " has type " << type << ", but the array holds "
                             << array.getElementType();
  return success();
}

// What an array op does besides computing: IO in the world's order, a
// crash where its index may be out of bounds, and for a new array an
// allocation.
void arrayEffects(std::optional<StringRef> crash, Value allocated,
                  SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  effects.emplace_back(MemoryEffects::Read::get(), IOResource::get());
  effects.emplace_back(MemoryEffects::Write::get(), IOResource::get());
  if (crash)
    effects.emplace_back(MemoryEffects::Write::get(), CrashResource::get());
  if (allocated)
    effects.emplace_back(MemoryEffects::Allocate::get(), cast<OpResult>(allocated),
                         SideEffects::DefaultResource::get());
}

// An index is a value the program computed, so it may be out of bounds;
// the check against the length (memref.dim) that the program's own test
// made redundant folds away after lowering.
constexpr StringRef outOfBounds = "array index out of bounds";

} // namespace

LogicalResult ArrayNewOp::verify() {
  return verifyElement(*this, "the fill", getFill().getType(), getArrayType());
}

LogicalResult ArrayGetOp::verify() {
  return verifyElement(*this, "the result", getValue().getType(), getArrayType());
}

LogicalResult ArraySetOp::verify() {
  return verifyElement(*this, "the value", getValue().getType(), getArrayType());
}

std::optional<StringRef> ArrayNewOp::getCrashCause() { return std::nullopt; }
std::optional<StringRef> ArrayGetOp::getCrashCause() { return outOfBounds; }
std::optional<StringRef> ArraySetOp::getCrashCause() { return outOfBounds; }

void ArrayNewOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  arrayEffects(getCrashCause(), getArray(), effects);
}
void ArrayGetOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  arrayEffects(getCrashCause(), Value(), effects);
}
void ArraySetOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  arrayEffects(getCrashCause(), Value(), effects);
}
