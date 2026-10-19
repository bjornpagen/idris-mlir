// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The idr ops, as TableGen defines them, with what the generated code calls
// by name and so must find declared before it: the custom directives of the
// ops' assembly formats (a constructor's name is Symbols.h's CtorRef), and
// the folders the divisions and remainders, and the shifts, share through
// IdrScalarOps.td. Every other hook of an op is defined in the unit of its
// family.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/DialectImplementation.h"
#include "mlir/IR/OpImplementation.h"
#include "llvm/ADT/DenseSet.h"

#include <concepts>

using namespace mlir;
using namespace idr;

//===----------------------------------------------------------------------===//
// Custom directives
//===----------------------------------------------------------------------===//

namespace {

// A type written only when it is not the plain type the op has by default
// (a big, a string, a natural), which the format gives as C++: `: !idr.nat`
// on a big op that computes on naturals, `: !idr.own<!idr.str>`.
ParseResult parseResultAtGrade(OpAsmParser &parser, Type &type, Type plain) {
  if (succeeded(parser.parseOptionalColon()))
    return parser.parseType(type);
  type = plain;
  return success();
}

void printResultAtGrade(OpAsmPrinter &printer, Operation *, Type type, Type plain) {
  if (type != plain)
    printer << ": " << type;
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

// A value an op reads in place: its operand, after `borrow` when it is the
// view the owned stage grades Borrow, and plain otherwise, its plain type
// the one the format gives as C++. The grade alone says what is printed.
ParseResult parseRead(OpAsmParser &parser, OpAsmParser::UnresolvedOperand &operand, Type &type,
                      Type plain) {
  type = succeeded(parser.parseOptionalKeyword("borrow")) ? view(plain) : plain;
  return parser.parseOperand(operand);
}

void printRead(OpAsmPrinter &printer, Operation *, Value operand, Type type, Type /*plain*/) {
  if (gradeOf(type).permission == Permission::Borrow)
    printer << "borrow ";
  printer << operand;
}

// `%a : A`: a field given, with its type.
ParseResult parseField(OpAsmParser &parser,
                       SmallVectorImpl<OpAsmParser::UnresolvedOperand> &fields,
                       SmallVectorImpl<Type> &types) {
  return failure(parser.parseOperand(fields.emplace_back()) ||
                 parser.parseColonType(types.emplace_back()));
}

// `(%a : A, %b : B)`: the fields of a constructor value, every one given
// with its type (idr.con).
ParseResult parseFields(OpAsmParser &parser,
                        SmallVectorImpl<OpAsmParser::UnresolvedOperand> &fields,
                        SmallVectorImpl<Type> &types) {
  return parser.parseCommaSeparatedList(OpAsmParser::Delimiter::Paren,
                                        [&]() { return parseField(parser, fields, types); });
}

void printFields(OpAsmPrinter &printer, Operation *, OperandRange fields, TypeRange types) {
  printer << '(';
  llvm::interleaveComma(llvm::zip_equal(fields, types), printer, [&](auto field) {
    printer << std::get<0>(field) << " : " << std::get<1>(field);
  });
  printer << ')';
}

// `(%a : A, dest, %b : B)`: the fields a cell's init writes, each given with
// its type, and a hole, a field written later through its destination, as
// `dest` (idr.cell.init). `holes` are the holes' field indices, ascending,
// and empty when there is none, so the destinations' directive reads them.
ParseResult parseFields(OpAsmParser &parser,
                        SmallVectorImpl<OpAsmParser::UnresolvedOperand> &fields,
                        SmallVectorImpl<Type> &types, DenseI32ArrayAttr &holes) {
  SmallVector<int32_t> at;
  int32_t index = 0;
  if (parser.parseCommaSeparatedList(OpAsmParser::Delimiter::Paren, [&]() -> ParseResult {
        if (succeeded(parser.parseOptionalKeyword("dest")))
          at.push_back(index);
        else if (failed(parseField(parser, fields, types)))
          return failure();
        ++index;
        return success();
      }))
    return failure();
  holes = parser.getBuilder().getDenseI32ArrayAttr(at);
  return success();
}

void printFields(OpAsmPrinter &printer, Operation *, OperandRange fields, TypeRange types,
                 DenseI32ArrayAttr holes) {
  ArrayRef<int32_t> at = holes ? holes.asArrayRef() : ArrayRef<int32_t>();
  printer << '(';
  size_t given = 0;
  for (size_t index = 0, n = fields.size() + at.size(); index < n; ++index) {
    if (index)
      printer << ", ";
    if (given == fields.size() || llvm::is_contained(at, static_cast<int32_t>(index))) {
      printer << "dest";
      continue;
    }
    printer << fields[given] << " : " << types[given];
    ++given;
  }
  printer << ')';
}

// The box a cell's init gives: the box of its cell's type, owned, unless
// written, `-> T`: an init whose result is another grade of that box (the
// plain box the cells step makes at stage first, the exclusive one the
// commit writes) prints it. The cell's type is checked here, before the
// destinations' directive reads it: the text may name any type there, and
// only a cell has a box and fields.
ParseResult parseCellResult(OpAsmParser &parser, Type &type, Type cell) {
  auto cellType = dyn_cast<CellType>(cell);
  if (!cellType)
    return parser.emitError(parser.getCurrentLocation(), "expected a cell's type, not ") << cell;
  if (succeeded(parser.parseOptionalArrow()))
    return parser.parseType(type);
  type = owned(atLifetime(cellType.getBox(), cellType.getLifetime()));
  return success();
}

void printCellResult(OpAsmPrinter &printer, Operation *, Type type, Type cell) {
  auto cellType = cast<CellType>(cell);
  if (type != owned(atLifetime(cellType.getBox(), cellType.getLifetime())))
    printer << " -> " << type;
}

// What a share gives: its value with its exclusivity forgotten (shared),
// unless written, `-> T`: a share that also raises the value's lifetime to
// the frame prints it.
ParseResult parseShared(OpAsmParser &parser, Type &type, Type value) {
  if (succeeded(parser.parseOptionalArrow()))
    return parser.parseType(type);
  type = shared(value);
  return success();
}

void printShared(OpAsmPrinter &printer, Operation *, Type type, Type value) {
  if (type != shared(value))
    printer << " -> " << type;
}

// Nothing: each destination is the one its hole's field has, which the
// init's own rule gives from the cell's type and the holes
// (CellInitOp::destTypes). The cell's type is one, its result's directive
// having read it first.
ParseResult parseCellDests(OpAsmParser &, SmallVectorImpl<Type> &dests, Type cell,
                           DenseI32ArrayAttr holes) {
  llvm::append_range(dests, CellInitOp::destTypes(cast<CellType>(cell), holes.asArrayRef()));
  return success();
}

void printCellDests(OpAsmPrinter &, Operation *, TypeRange, Type, DenseI32ArrayAttr) {}

//===----------------------------------------------------------------------===//
// Division and shifts, shared through IdrScalarOps.td
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
concept DivisionOp = requires(Division op, typename Division::FoldAdaptor adaptor) {
  { Division::quotient } -> std::convertible_to<bool>;
  { Division::isSigned } -> std::convertible_to<bool>;
  { Division::guardHolds(adaptor) } -> std::convertible_to<bool>;
  op.getLhs();
  op.getRhs();
};

// Nothing by a divisor its guard refuses: the program never divides by it,
// since the guard crashes first, and APInt would abort the compiler. Where
// the guard holds, the divisor is a constant, an integer's, not zero.
template <DivisionOp Division>
OpFoldResult foldDivision(Division op, typename Division::FoldAdaptor adaptor) {
  if (!Division::guardHolds(adaptor))
    return {};
  auto rhs = cast<IntegerAttr>(adaptor.getRhs());
  if (rhs.getValue().isOne())
    return Division::quotient ? OpFoldResult(op.getLhs())
                              : OpFoldResult(IntegerAttr::get(op.getType(), 0));
  auto lhs = dyn_cast_or_null<IntegerAttr>(adaptor.getLhs());
  if (!lhs)
    return {};
  auto [q, r] = idrisDivMod(lhs.getValue(), rhs.getValue(), Division::isSigned);
  return IntegerAttr::get(op.getType(), Division::quotient ? q : r);
}

// Idris's shift (Idr_ShiftOp): `a` moved `amount` places, left or right,
// the other way when a signed amount is negative; a right shift fills with
// the sign when signed and with zeros when not, and the bits past the width
// are dropped, so from the width up a shift leaves only the fill.
APInt idrisShift(const APInt &a, const APInt &amount, bool left, bool isSigned) {
  unsigned width = a.getBitWidth();
  bool toLeft = left;
  APInt places = amount;
  if (isSigned && amount.isNegative()) {
    toLeft = !toLeft;
    // The most negative amount stays negative, which reads as a huge count.
    places = -amount;
  }
  if (places.uge(width)) {
    if (toLeft || !isSigned || !a.isNegative())
      return APInt::getZero(width);
    return APInt::getAllOnes(width);
  }
  unsigned n = static_cast<unsigned>(places.getZExtValue());
  if (toLeft)
    return a.shl(n);
  return isSigned ? a.ashr(n) : a.lshr(n);
}

template <typename Shift>
concept ShiftOp = requires(Shift op) {
  { Shift::left } -> std::convertible_to<bool>;
  { Shift::isSigned } -> std::convertible_to<bool>;
  op.getLhs();
  op.getRhs();
};

template <ShiftOp Shift>
OpFoldResult foldShift(Shift op, typename Shift::FoldAdaptor adaptor) {
  auto rhs = dyn_cast_or_null<IntegerAttr>(adaptor.getRhs());
  if (rhs && rhs.getValue().isZero())
    return op.getLhs();
  auto lhs = dyn_cast_or_null<IntegerAttr>(adaptor.getLhs());
  if (!lhs || !rhs)
    return {};
  return IntegerAttr::get(op.getType(),
                          idrisShift(lhs.getValue(), rhs.getValue(), Shift::left, Shift::isSigned));
}

} // namespace

#include "idr/IR/IdrInterfaces.cpp.inc"

#define GET_OP_CLASSES
#include "idr/IR/IdrOps.cpp.inc"
