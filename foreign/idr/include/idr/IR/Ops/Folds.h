// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Each composite fold's condition (FoldParts.h), written once over where a
// constant or a value lives: the attribute fold asks it of the constants
// and values of the program, and the e-graph of its own, whether an op held
// them or the graph made them. Each reads what its op says of itself (its
// data type, its index, whether its value's built state holds where it
// reads it) and asks the place for the rest: a constant's cells, or the op
// that built a value. IdrDialect.h includes this after the op classes that
// declare `meaning`.
#ifndef IDR_IR_OPS_FOLDS_H
#define IDR_IR_OPS_FOLDS_H

#include "idr/IR/FoldParts.h"
#include "idr/IR/Symbols.h"

#include "llvm/ADT/APInt.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/TargetParser/Triple.h"

#include <cstdint>
#include <optional>

namespace idr {

namespace families {

// The field `read` takes from the constructor `con` built its value with:
// the field given, where the read takes it at the type it was given, a
// field used once only by the constructor's one read of it, and the value's
// built state still holds where it is read; null otherwise. One answer for
// the field read's fold and for the skeleton rule of a read the e-graph
// keeps in place (FieldOfCon).
mlir::Value givenField(DataConOp con, DataFieldOp read);

} // namespace families

namespace platform {

// The target the module holding `op` names, where it names one: the one
// place the target is decided, which idr-target writes.
std::optional<llvm::Triple> targetOf(mlir::Operation *op);
// The operating system of a target of ours, as Idris's Scheme backends
// spell it for base; none for a system of no target of ours.
std::optional<llvm::StringRef> osName(const llvm::Triple &triple);

} // namespace platform

// A constructor of constants is a constant, where nothing reads which value
// it is: not a memo cell, which a force writes, nor a value of a family
// rebuilt in place or one used once, each of which is its own. Each field
// is one a constant constructor holds at its own type (the one leaf rule,
// so a poison, the program's value where control never arrives, keeps the
// constructor an op), and the constant stands where idr.constant holds it
// at the result's type, which the place decides.
template <fold::Composite W>
std::optional<typename W::Result> DataConOp::meaning(W &where, DataConOp op,
                                                    llvm::ArrayRef<typename W::Operand> constants) {
  DataType data = op.getDataType();
  mlir::Type result = op.getResult().getType();
  if (data.kind() != MemberKind::Data || data.promise() == Promise::InPlace ||
      usesOf(result) == Uses::Once)
    return std::nullopt;
  mlir::OperandRange fields = op.getFields();
  llvm::ArrayRef<typename W::Operand> held =
      constants.slice(fields.getBeginOperandIndex(), fields.size());
  for (auto [constant, field] : llvm::zip_equal(held, fields))
    if (!where.buildable(constant, field.getType()))
      return std::nullopt;
  return where.constructor(result, data, held);
}

// The one constructor the type leaves possible, as it is of every value an
// idr.data.con builds, whose type is refined to its constructor; else,
// where the value's built state still holds where it is read, the
// constructor of the constant it is.
template <fold::Composite W>
std::optional<typename W::Result> DataTagOp::meaning(W &where, DataTagOp op,
                                                    llvm::ArrayRef<typename W::Operand> constants) {
  auto data = llvm::dyn_cast<DataType>(unrestricted(op.getValue().getType()));
  if (!data)
    return std::nullopt;
  std::optional<Tag> tag = data.singleTag();
  if (!tag && builtStateHolds(op.getValue(), op.getOperation()))
    if (std::optional<typename W::Cell> cell = where.cellOf(constants[0]))
      tag = where.tagAt(*cell);
  if (!tag)
    return std::nullopt;
  return where.integer(op.getType(), llvm::APInt(64, static_cast<std::uint64_t>(*tag)));
}

// A field of a known constructor: the field the idr.data.con that built the
// value was given (givenField, which says where the read may take it). Or a
// field of a constant, read in place, where the value's built state still
// holds where it is read: off a run's spine that costs nothing however long
// the run is. A constant is no linear value, so a linear field of one stays
// a read.
template <fold::Composite W>
std::optional<fold::Folded<W>>
DataFieldOp::meaning(W &where, DataFieldOp op, llvm::ArrayRef<typename W::Operand> constants) {
  auto index = static_cast<unsigned>(op.getIndex());
  if (auto con = where.template builtBy<DataConOp>(op.getValue(), constants[0])) {
    if (!families::givenField(con->op, op))
      return std::nullopt;
    return fold::Folded<W>(con->operands[con->op.getFields().getBeginOperandIndex() + index]);
  }
  if (isLinear(op.getType()) || !builtStateHolds(op.getValue(), op.getOperation()))
    return std::nullopt;
  if (std::optional<typename W::Result> field = where.fieldOf(constants[0], index, op.getType()))
    return fold::Folded<W>(std::move(*field));
  return std::nullopt;
}

// The QTT rule: a cast back of a cast whose result nothing else uses is the
// value itself, nothing having run in the linear position; a value cast
// into a linear position and used elsewhere too stays, since folding it
// would use the value twice. The value lives at least as long as either
// cast states, so what used the outer cast may use it.
template <fold::Composite W>
std::optional<fold::Folded<W>> LinCastOp::meaning(W &where, LinCastOp op,
                                                  llvm::ArrayRef<typename W::Operand> constants) {
  auto inner = where.template builtBy<LinCastOp>(op.getValue(), constants[0]);
  if (!inner || inner->op.getValue().getType() != op.getType() || !inner->op->hasOneUse())
    return std::nullopt;
  return fold::Folded<W>(inner->operands[0]);
}

// No axis tied, nothing to say; the same sizes of the same axes said
// twice, once.
template <fold::Composite W>
std::optional<fold::Folded<W>>
ArrayTieShapeOp::meaning(W &where, ArrayTieShapeOp op, llvm::ArrayRef<typename W::Operand> constants) {
  if (op.getDims().empty())
    return fold::Folded<W>(where.given(op.getValue(), constants[0]));
  auto inner = where.template builtBy<ArrayTieShapeOp>(op.getValue(), constants[0]);
  if (inner && inner->op.getAxes() == op.getAxes() && inner->op.getDims() == op.getDims())
    return fold::Folded<W>(where.given(op.getValue(), constants[0]));
  return std::nullopt;
}

// A constant numeral's value is its successor layers, read in place a run
// at a time (fold::numeralLayers). It is a natural in the small range,
// which the runtime holds in its word: each layer is a cell the constant
// holds.
template <fold::Composite W>
std::optional<typename W::Result>
NumeralToNatOp::meaning(W &where, NumeralToNatOp op, llvm::ArrayRef<typename W::Operand> constants) {
  auto data = llvm::cast<DataType>(unrestricted(op.getValue().getType()));
  std::optional<std::uint64_t> layers = fold::numeralLayers(where, constants[0], data);
  if (!layers)
    return std::nullopt;
  return where.big(op.getType(),
                   runtime::Abi<BigSmallOp>::function(static_cast<std::int64_t>(*layers)));
}

// The runtime packs a list of characters as the cons of each onto the
// rest, from the empty string, by str.cons's function; the elements are
// read off the list's cells in place, and consed from the last. Each
// step's scope holds the string before it, released once the next is made
// from it, which the runtime makes fresh: a fold holds a fixed number of
// references however long the list, and the last string is the place's.
template <fold::Composite W>
std::optional<typename W::Result>
StrPackOp::meaning(W &where, StrPackOp op, llvm::ArrayRef<typename W::Operand> constants) {
  families::ListShape shape =
      *llvm::cast<DataType>(unrestricted(op.getList().getType())).listShape();
  std::optional<footprint::Vector<typename W::Cell>> cells =
      fold::elementCells(where, constants[0], shape);
  if (!cells)
    return std::nullopt;
  const idris_rt_str *s = idris_rt_str_from_utf8("", 0);
  for (const typename W::Cell &cell : llvm::reverse(*cells)) {
    fold::Scope step(op.getContext());
    step.keep(s);
    std::optional<llvm::APInt> scalar = where.integerAt(cell, shape.element);
    if (!scalar)
      return std::nullopt;
    s = runtime::Abi<StrConsOp>::function(static_cast<std::int32_t>(scalar->getSExtValue()), s);
  }
  return where.str(op.getType(), s);
}

// The runtime concatenates a list of strings as the append of each, in
// order, by str.append's function, read off the list's cells in place;
// each step's scope holds the string before it and the element's own where
// the place made it, so a fold holds a fixed number of references however
// long the list, and the last string is the place's.
template <fold::Composite W>
std::optional<typename W::Result>
StrConcatOp::meaning(W &where, StrConcatOp op, llvm::ArrayRef<typename W::Operand> constants) {
  families::ListShape shape =
      *llvm::cast<DataType>(unrestricted(op.getList().getType())).listShape();
  std::optional<footprint::Vector<typename W::Cell>> cells =
      fold::elementCells(where, constants[0], shape);
  if (!cells)
    return std::nullopt;
  const idris_rt_str *s = idris_rt_str_from_utf8("", 0);
  for (const typename W::Cell &cell : *cells) {
    fold::Scope step(op.getContext());
    step.keep(s);
    std::optional<const idris_rt_str *> piece = where.strAt(step, cell, shape.element);
    if (!piece)
      return std::nullopt;
    s = runtime::Abi<StrAppendOp>::function(s, *piece);
  }
  return where.str(op.getType(), s);
}

// The constant is the same value under the other type, where idr.constant
// holds it there.
template <fold::Composite W>
std::optional<typename W::Result>
NatToBigOp::meaning(W &where, NatToBigOp op, llvm::ArrayRef<typename W::Operand> constants) {
  return where.same(op.getResult().getType(), constants[0]);
}

// The operating system the module's target names, as the string base tests
// for; a module that names no target of ours has none to give, and the op
// stays, never the build machine's.
template <fold::Composite W>
std::optional<typename W::Result> PlatformOsOp::meaning(W &where, PlatformOsOp op,
                                                       llvm::ArrayRef<typename W::Operand>) {
  std::optional<llvm::Triple> target = platform::targetOf(op.getOperation());
  if (!target)
    return std::nullopt;
  std::optional<llvm::StringRef> os = platform::osName(*target);
  if (!os)
    return std::nullopt;
  return where.str(op.getType(), idris_rt_str_from_utf8(os->data(), os->size()));
}

} // namespace idr

#endif // IDR_IR_OPS_FOLDS_H
