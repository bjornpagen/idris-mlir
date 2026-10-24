// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Each composite fold's condition (FoldParts.h), written once over where a
// constant lives: the attribute fold asks it of the constants ops hold, and
// the e-graph of its own values, whether an op held them or the graph made
// them. Each reads what its op says of itself (its data type, its index,
// whether its value's built state holds where it reads it) and asks the
// place for the rest. IdrDialect.h includes this after the op classes that
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

// A closure of constants is an immutable value nothing reads the identity
// of, so it is the constant idr.constant holds at its type. Essential, two
// closures: a constant closure holds no index terms, so one at terms stays
// an op.
template <fold::Composite W>
std::optional<typename W::Result>
FnClosureOp::meaning(W &where, FnClosureOp op, llvm::ArrayRef<typename W::Operand> constants) {
  if (op.getIndexArgs().getCount() != 0)
    return std::nullopt;
  mlir::OperandRange captures = op.getCaptures();
  llvm::ArrayRef<typename W::Operand> held =
      constants.slice(captures.getBeginOperandIndex(), captures.size());
  for (auto [constant, capture] : llvm::zip_equal(held, captures))
    if (!where.buildable(constant, capture.getType()))
      return std::nullopt;
  return where.closure(op.getType(), op.getCalleeAttr(), held);
}

// The one constructor the type leaves possible; else the constructor of a
// constant, where the value's built state still holds where it is read.
template <fold::Composite W>
std::optional<typename W::Result> DataTagOp::meaning(W &where, DataTagOp op,
                                                    llvm::ArrayRef<typename W::Operand> constants) {
  auto data = llvm::dyn_cast<DataType>(unrestricted(op.getValue().getType()));
  if (!data)
    return std::nullopt;
  std::optional<Tag> tag = data.singleTag();
  if (!tag && builtStateHolds(op.getValue(), op.getOperation()))
    tag = where.tagOf(constants[0]);
  if (!tag)
    return std::nullopt;
  return where.integer(op.getType(), llvm::APInt(64, static_cast<std::uint64_t>(*tag)));
}

// A field of a constant, read in place, where the value's built state still
// holds where it is read: off a run's spine that costs nothing however long
// the run is. A constant is no linear value, so a linear field of one stays
// a read.
template <fold::Composite W>
std::optional<typename W::Result>
DataFieldOp::meaning(W &where, DataFieldOp op, llvm::ArrayRef<typename W::Operand> constants) {
  if (isLinear(op.getType()) || !builtStateHolds(op.getValue(), op.getOperation()))
    return std::nullopt;
  return where.fieldOf(constants[0], static_cast<unsigned>(op.getIndex()), op.getType());
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
