// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The skeleton rules of constructor values. Each decides over what the
// e-graph knows of its root's operands (the op that made each one's chosen
// form), and carries its decision out on the root as it then is, checking
// its condition again there, since the input may hold the forms the e-graph
// equated apart.

#include "idr/IR/Families/Rules.h"

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"

#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;
using namespace idr;

Value families::givenField(DataConOp con, DataFieldOp read) {
  auto index = static_cast<unsigned>(read.getIndex());
  if (!builtStateHolds(con.getResult(), read.getOperation()))
    return {};
  Value field = con.getFields()[index];
  if (field.getType() != read.getType())
    return {};
  if (usesOf(field.getType()) == Uses::Once && !fieldReadOnce(con.getResult(), index))
    return {};
  return field;
}

namespace {

// Whether `con`'s result must stay a value of its own: something reads
// which value it is (a memo cell, a frame, a family rebuilt in place, a
// value used once), or it lives in the lifetime `con` states, which the
// value it was rebuilt from need not outlive.
bool ownValue(DataConOp con) {
  DataType data = con.getDataType();
  Type result = con.getResult().getType();
  return data.kind() != MemberKind::Data || data.promise() == Promise::InPlace ||
         usesOf(result) == Uses::Once || !con.getOuters().empty();
}

// The value `con` rebuilds: each field it is given is the same field of
// one value of `con`'s own type, read at the type it was given; null
// otherwise. `originOf` gives the op that made a field's form.
template <class OriginOf>
Value rebuiltValue(DataConOp con, OriginOf &&originOf) {
  if (ownValue(con) || con.getFields().empty())
    return {};
  Value whole;
  for (auto [index, field] : llvm::enumerate(con.getFields())) {
    auto read = dyn_cast_or_null<DataFieldOp>(originOf(field));
    if (!read || read.getIndex() != index || read.getType() != field.getType() ||
        (whole && read.getValue() != whole))
      return {};
    whole = read.getValue();
  }
  return whole.getType() == con.getResult().getType() ? whole : Value();
}

} // namespace

namespace idr::egraph {

std::optional<Edit> FieldOfCon::decide(Root op, const OperandFacts &facts) {
  auto con = dyn_cast_or_null<DataConOp>(facts.origin(op.getValue()));
  if (!con || !families::givenField(con, op))
    return std::nullopt;
  return Rewrite{};
}

void FieldOfCon::rewrite(Root op, const Rewrite &, RewriterBase &rewriter) {
  auto con = op.getValue().getDefiningOp<DataConOp>();
  if (!con)
    return;
  if (Value field = families::givenField(con, op))
    rewriter.replaceOp(op, field);
}

std::optional<Edit> ConEta::decide(Root op, const OperandFacts &facts) {
  if (!rebuiltValue(op, [&](Value field) { return facts.origin(field); }))
    return std::nullopt;
  return Rewrite{};
}

void ConEta::rewrite(Root op, const Rewrite &, RewriterBase &rewriter) {
  if (Value whole = rebuiltValue(op, [](Value field) { return field.getDefiningOp(); }))
    rewriter.replaceOp(op, whole);
}

} // namespace idr::egraph
