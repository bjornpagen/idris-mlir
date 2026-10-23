// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The ops of refinement and of numerals: idr.data.reindex, a value at a
// type its enclosing refinements make equal to its own, which says by its
// types whether it gives that value on with no run-time work;
// idr.index.assume, a region in which an erased equality holds; and the two
// conversions between a numeral and a natural, the first carrying the bound
// its operand's type proves into the natural's range. Each op checks here
// what it says alone; that a cast's two types are equal under the
// refinements around it is the function's scope walk's, which holds them.

#include "idr/IR/Families/Families.h"
#include "idr/IR/Families/Scope.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Lifetimes.h"
#include "idr/IR/Ranges.h"

#include "mlir/IR/OpImplementation.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;
using namespace idr;
using namespace idr::families;

//===----------------------------------------------------------------------===//
// idr.data.reindex
//===----------------------------------------------------------------------===//

// A scoped value cast stays where it lives: the cast states the operand's
// lifetime, which it passes through.
void DataReindexOp::build(OpBuilder &builder, OperationState &state, Type result, Value value) {
  SmallVector<Value, 1> outers;
  if (Value lifetime = lifetimes::statedLifetime(value);
      lifetime && freedBy(result, Release::Scoped))
    outers.push_back(lifetime);
  build(builder, state, result, value, outers);
}

// One carrier is the other at some instance of its levels, or a refinement
// of it: a cast of anything else could be no refinement's. A grade is no
// index term, so what refines is the carriers, and the grade the result
// takes is the cast's own, by what its re-pack does. Either way the value
// is the one Idris proved, so its uses are kept. A reindex that builds a
// cell or an array gives a fresh value, counted and claimed unique
// whatever the operand's hold, none among them (words in place hold no
// reference), which counting frees as any fresh value. One that builds
// nothing, free or not (a cell taken apart in place, a numeral widened),
// keeps the operand's hold, its result's memory the operand's, wherever
// both hold references. Whether it builds is the one answer the lowering's
// re-pack reads too, here at the field types the layouts lay out, which a
// verifier may make; a re-pack that works builds nothing where it only
// takes a cell apart, so whether the cast is free does not decide it.
LogicalResult DataReindexOp::verify() {
  Type from = getValue().getType();
  Type to = getType();
  Type fromCarrier = unrestricted(from);
  Type toCarrier = unrestricted(to);
  if (!refines(fromCarrier, toCarrier) && !refines(toCarrier, fromCarrier))
    return emitOpError("casts ") << from << " to " << to
                                 << ", which no refinement of index terms relates";
  if (usesOf(from) != usesOf(to))
    return emitOpError("casts one value, so it keeps its uses; ") << from << " is given as " << to;
  auto laidOut = [](DataType type, Tag tag) { return Layouts::fieldsAt(type, tag); };
  if (families::builds(from, to, laidOut)) {
    if (!freedBy(to, Release::Counted) || !claims(to, Unique::Self))
      return emitOpError("builds a cell or an array, a fresh value, so its result is counted and ")
             << "claimed unique; it gives " << to;
  } else if (std::optional<Hold> given = holdOf(from), made = holdOf(to);
             given && made && *given != *made) {
    return emitOpError("builds nothing, its result's memory its operand's, so it keeps the ")
           << "operand's hold; " << from << " is given as " << to;
  }
  return lifetimes::verifyOuters(*this, 0);
}

Value DataReindexOp::getStatedLifetime(Value made) {
  return lifetimes::statedOuter(*this, made, 0);
}
void DataReindexOp::setStatedLifetime(Value made, Value lifetime) {
  lifetimes::stateOuter(*this, made, lifetime, 0);
}

// A cast to its operand's own type is the operand; a cast of a cast casts
// the first operand.
OpFoldResult DataReindexOp::fold(FoldAdaptor) {
  if (getValue().getType() == getType())
    return getValue();
  if (auto inner = getValue().getDefiningOp<DataReindexOp>()) {
    getValueMutable().assign(inner.getValue());
    return getResult();
  }
  return {};
}

// Free where its two types are the same words at run time, as their layout
// facts, computed when each was made, say.
bool DataReindexOp::isFree() {
  return families::layoutMatch(getValue().getType(), getType()) == LayoutMatch::SameLayout;
}

// It gives its operand on with no run-time work exactly where it is free:
// a re-pack is work after the value it takes, which a call whose result it
// takes would have to wait for.
Carry DataReindexOp::getCarry() { return isFree() ? Carry::Free : Carry::Works; }

// A re-pack builds the cells its result needs where an index known inside
// a function changes the layout, so it stays where it is.
Speculation::Speculatability DataReindexOp::getSpeculatability() {
  return isFree() ? Speculation::Speculatable : Speculation::NotSpeculatable;
}

//===----------------------------------------------------------------------===//
// idr.index.assume
//===----------------------------------------------------------------------===//

// Its region binds the forwarded values, each at its refined type, one per
// operand.
LogicalResult IndexAssumeOp::verify() {
  Region &body = getBody();
  if (body.empty() || body.getNumArguments() != getForwarded().size())
    return emitOpError("expects its region to bind each value it forwards");
  return success();
}

ArrayRef<Sort> IndexAssumeOp::getBoundSorts(Region &) { return {}; }

std::optional<RegionRefinement> IndexAssumeOp::getRefinement(Region &) {
  EquationAttr equation = getEquation();
  return RegionRefinement{equation.getLhs(), equation.getRhs(), 1, Scoped::Enclosing,
                          FamilyAttr()};
}

void IndexAssumeOp::getSuccessorRegions(RegionBranchPoint point,
                                        SmallVectorImpl<RegionSuccessor> &successors) {
  if (point.isParent()) {
    successors.emplace_back(&getBody());
    return;
  }
  successors.emplace_back(getOperation());
}

OperandRange IndexAssumeOp::getEntrySuccessorOperands(RegionSuccessor) { return getForwarded(); }

// The body binds each value forwarded; the op's results take what the body
// yields.
ValueRange IndexAssumeOp::getSuccessorInputs(RegionSuccessor successor) {
  if (successor.isOperation())
    return getResults();
  return successor.getSuccessor()->getArguments();
}

// A value enters refined and leaves cast back: the scope walk checks each
// against the equation, which no context-free comparison sees.
bool IndexAssumeOp::areTypesCompatible(Type lhs, Type rhs) {
  return lhs == rhs || refines(lhs, rhs) || refines(rhs, lhs);
}

// `idr.index.assume <lhs = rhs> (%v : T) -> (R) { ^bb0(%w : T'): ... }`.
void IndexAssumeOp::print(OpAsmPrinter &printer) {
  printer << ' ';
  printer.printAttributeWithoutType(getEquationAttr());
  printer << " (";
  llvm::interleaveComma(getForwarded(), printer, [&](Value value) {
    printer << value << " : " << value.getType();
  });
  printer << ") -> (" << getResultTypes() << ") ";
  printer.printRegion(getBody(), /*printEntryBlockArgs=*/true);
  printer.printOptionalAttrDict((*this)->getAttrs(), {"equation"});
}

ParseResult IndexAssumeOp::parse(OpAsmParser &parser, OperationState &state) {
  EquationAttr equation;
  SmallVector<OpAsmParser::UnresolvedOperand> forwarded;
  SmallVector<Type> types, results;
  if (parser.parseAttribute(equation) || parser.parseLParen())
    return failure();
  if (failed(parser.parseOptionalRParen())) {
    do {
      if (parser.parseOperand(forwarded.emplace_back()) ||
          parser.parseColonType(types.emplace_back()))
        return failure();
    } while (succeeded(parser.parseOptionalComma()));
    if (parser.parseRParen())
      return failure();
  }
  if (parser.parseArrow() || parser.parseLParen())
    return failure();
  if (failed(parser.parseOptionalRParen()) &&
      (parser.parseTypeList(results) || parser.parseRParen()))
    return failure();
  state.getOrAddProperties<Properties>().equation = equation;
  if (parser.resolveOperands(forwarded, types, parser.getCurrentLocation(), state.operands))
    return failure();
  state.addTypes(results);
  return failure(parser.parseRegion(*state.addRegion()) ||
                 parser.parseOptionalAttrDict(state.attributes));
}

//===----------------------------------------------------------------------===//
// Numerals
//===----------------------------------------------------------------------===//

namespace {

// The data type of a numeral value, at any grade.
DataType numeralOf(Type type) {
  auto data = dyn_cast<DataType>(unrestricted(type));
  return data && data.getGroup().shape(data.getMember()) == Shape::Numeral ? data : DataType();
}

} // namespace

LogicalResult NumeralToNatOp::verify() {
  if (!numeralOf(getValue().getType()))
    return emitOpError("reads ") << getValue().getType() << ", which is no numeral";
  return success();
}

// At most the largest value the operand's type allows, which the type kept
// when it was made (`#Fin[3]` gives 0 to 2), read as unsigned since a
// numeral is never negative; a natural's range where its index fixes no
// bound.
void NumeralToNatOp::inferResultRanges(ArrayRef<ConstantIntRanges>,
                                       SetIntRangeFn setResultRange) {
  ConstantIntRanges proved = idr::ranges::ofType(getValue().getType()).getValue();
  setResultRange(getResult(), idr::ranges::rangeOf(idr::ranges::ofInteger(
                                  proved, idr::numeric::Signedness::Unsigned)));
}

LogicalResult NumeralOfNatOp::verify() {
  if (!numeralOf(getType()))
    return emitOpError("gives ") << getType() << ", which is no numeral";
  return success();
}

// The number of a constant numeral's successor layers, read off its run of
// cells, however long: each run's last cell holds the next constant of the
// numeral, which the constant's verifier holds it to, until a cell of its
// zero.
uint64_t idr::families::numeralValue(ConAttr numeral) {
  uint64_t layers = 0;
  for (ConAttr at = numeral; !at.getData().ctor(at.getTag()).fields.empty();) {
    layers += at.getRunLength();
    ArrayAttr last = at.getCell(at.getRunLength() - 1);
    at = cast<ConAttr>(last[static_cast<unsigned>(at.getSpine())]);
  }
  return layers;
}

// A constant numeral's value is its successor layers.
OpFoldResult NumeralToNatOp::fold(FoldAdaptor adaptor) {
  auto con = dyn_cast_or_null<ConAttr>(adaptor.getValue());
  if (!con)
    return {};
  return BigAttr::get(getContext(), APInt(64, families::numeralValue(con)));
}
