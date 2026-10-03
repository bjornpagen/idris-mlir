// The idr ops, as TableGen defines them, with what the generated code calls
// by name and so must find declared before it: the custom directives of the
// ops' assembly formats, and the folder idr.div and idr.mod share through
// IdrOps.td. Every other hook of an op is defined in the unit of its family.

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

} // namespace

#include "idr/IdrInterfaces.cc.inc"

#define GET_OP_CLASSES
#include "idr/IdrOps.cc.inc"
