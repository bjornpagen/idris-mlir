// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a value's type says of its data, a constructor written by its label,
// the elimination of a value at one of its uses, and the names the lowering
// reserves.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"
#include "idr/IR/Families/Families.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/Twine.h"

using namespace mlir;
using namespace idr;

DataType idr::dataTypeOf(Type type) { return dyn_cast<DataType>(unrestricted(type)); }

bool idr::builtStateHolds(Value value, Operation *reader) {
  DataType data = dataTypeOf(value.getType());
  if (!data || !data.memo())
    return true;
  if (!value.getDefiningOp<DataConOp>())
    return false;
  return llvm::all_of(value.getUsers(), [&](Operation *user) {
    return !isa<MemoRunOp>(user) || reader->isAncestor(user);
  });
}

ParseResult idr::parseCtorRef(AsmParser &parser, Type type, IntegerAttr &tag) {
  SMLoc at = parser.getCurrentLocation();
  StringAttr label;
  if (parser.parseSymbolName(label))
    return failure();
  DataType data = dataTypeOf(type);
  if (!data)
    return parser.emitError(at, "names a constructor of ") << type << ", which is no data type";
  std::optional<Tag> found = data.getGroup().tagOf(data.getMember(), label.getValue());
  if (!found)
    return parser.emitError(at, "expects a constructor of ")
           << type << ", got @" << label.getValue();
  tag = parser.getBuilder().getI32IntegerAttr(static_cast<int32_t>(*found));
  return success();
}

void idr::printCtorRef(OpAsmPrinter &printer, Operation *, Type type, IntegerAttr tag) {
  printer.printSymbolName(dataTypeOf(type).ctor(Tag{static_cast<uint32_t>(tag.getInt())}).label);
}

std::optional<idr::Elimination> idr::eliminationAt(OpOperand &use) {
  // The only user of `v`, if it has one.
  auto next = [](Value v) { return v.hasOneUse() ? *v.user_begin() : nullptr; };
  auto isClosures = [](Value v) {
    DataType data = dataTypeOf(v.getType());
    return data && data.closures();
  };
  Elimination e;
  Value value = use.get();
  Operation *user = use.getOwner();
  if (auto enter = dyn_cast<LinCastOp>(user); enter && enter.getDirection() == QuantityChange::Enter) {
    auto exit = dyn_cast_or_null<LinCastOp>(next(enter.getResult()));
    if (!exit || exit.getDirection() != QuantityChange::Leave)
      return std::nullopt;
    e.passed = {enter, exit};
    user = next(value = exit.getResult());
  }
  if (auto field = dyn_cast_or_null<DataFieldOp>(user); field && !isClosures(field.getValue())) {
    e.field = field;
    user = next(value = field.getResult());
  }
  if (auto linear = dyn_cast_or_null<LinCastOp>(user);
      linear && linear.getDirection() == QuantityChange::Leave) {
    e.use = linear;
    user = next(value = linear.getResult());
  }
  // The dispatch takes the value apart and does nothing else with it, which
  // its op declares (EliminatesOperand: a match, a field read, a string's
  // output), so no op is named here. What raising dispatches on is what a
  // tail builds, a closure sum or a string; a match or a field read is
  // declared over every family, and a value of any other family is never
  // dispatched on (a field of one is a step, read above).
  DataType data = dataTypeOf(value.getType());
  if (!user || !user->hasTrait<EliminatesOperand>() || user->getOperand(0) != value ||
      (data && !data.closures()))
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
