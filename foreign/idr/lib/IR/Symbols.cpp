// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a data type's body says, read from a value's type, the elimination
// of a value at one of its uses, and the names the lowering reserves. The
// data types a pass remakes where a body would change are
// lib/IR/DataRemap.cpp's, and the names from content
// lib/IR/ContentNames.cpp's.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/Twine.h"
#include "llvm/ADT/TypeSwitch.h"

using namespace mlir;
using namespace idr;

DataType idr::dataTypeOf(Type type) {
  return TypeSwitch<Type, DataType>(unrestricted(type))
      .Case([](DataType data) { return data; })
      .Case([](BoxType box) { return box.getData(); })
      .Default([](Type) { return DataType(); });
}

bool idr::isBoxed(Type type) { return isa<BoxType>(unrestricted(type)); }

bool idr::builtStateHolds(Value value, Operation *reader) {
  DataType data = dataTypeOf(value.getType());
  if (!data || !data.isMemo())
    return true;
  if (!value.getDefiningOp<ConOp>())
    return false;
  return llvm::all_of(value.getUsers(), [&](Operation *user) {
    return !isa<MemoEnterOp, MemoSettleOp>(user) || reader->isAncestor(user);
  });
}

std::optional<idr::Elimination> idr::eliminationAt(OpOperand &use) {
  // The only user of `v`, if it has one.
  auto next = [](Value v) { return v.hasOneUse() ? *v.user_begin() : nullptr; };
  Elimination e;
  Value value = use.get();
  Operation *user = use.getOwner();
  if (auto enter = dyn_cast<LinEnterOp>(user)) {
    auto exit = dyn_cast_or_null<LinUseOp>(next(enter.getResult()));
    if (!exit)
      return std::nullopt;
    e.passed = {enter, exit};
    user = next(value = exit.getResult());
  }
  if (auto field = dyn_cast_or_null<FieldOp>(user); field && !field.getDataType().isClosures()) {
    e.field = field;
    user = next(value = field.getResult());
  }
  if (auto linear = dyn_cast_or_null<LinUseOp>(user)) {
    e.use = linear;
    user = next(value = linear.getResult());
  }
  auto eliminates = [&](Operation *op) {
    if (auto match = dyn_cast_or_null<MatchOp>(op))
      return match.getScrutinee() == value && match.getDataType().isClosures();
    if (auto field = dyn_cast_or_null<FieldOp>(op))
      return field.getValue() == value && field.getDataType().isClosures();
    if (auto output = dyn_cast_or_null<PutStrOp>(op))
      return output.getStr() == value;
    return false;
  };
  if (!eliminates(user))
    return std::nullopt;
  e.dispatch = user;
  return e;
}

SmallVector<Operation *> idr::Elimination::steps() const {
  SmallVector<Operation *> out;
  if (passed)
    out.append({passed->first, passed->second});
  if (field)
    out.push_back(*field);
  if (use)
    out.push_back(*use);
  return out;
}

std::string idr::reservedName(StringRef kind, StringRef discriminator) {
  return ("__idr$" + kind + "$" + discriminator).str();
}

std::string idr::releaseCafsName() { return reservedName("release", "cafs"); }
