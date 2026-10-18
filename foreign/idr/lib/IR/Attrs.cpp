// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The check of the dialect's attributes beyond their syntax: a big has one
// width. And refusals: the one place their words are written, with the rule
// carried as data in the diagnostic.

#include "idr/IR/IdrDialect.h"

// categoryOf: the kind of program each rule refuses, written from the
// category each case of Idr_Rule names in its ODS (idris-mlir-tblgen
// -gen-rule-categories).
#include "idr/IR/IdrRuleCategories.inc"

using namespace mlir;
using namespace idr;

// One width per integer, its fewest signed bits, so that equal bigs are
// equal attributes.
LogicalResult BigAttr::verify(function_ref<InFlightDiagnostic()> emitError, APInt value) {
  if (value.getBitWidth() != value.getSignificantBits())
    return emitError() << "expects a big at its fewest signed bits, "
                       << value.getSignificantBits() << ", got " << value.getBitWidth();
  return success();
}

// The two kinds of words a refusal begins with are the problem's: a
// construct this compiler does not compile is named by its rule, and a
// program Idris rejects is refused in Idris's own words alone.
std::string idr::refusalHead(Rule rule) {
  if (categoryOf(rule) == RuleCategory::UserError)
    return "";
  return ("unsupported (" + stringifyRule(rule) + "): ").str();
}

// The rule rides in the diagnostic's metadata, which no handler prints, so
// the message reads as it always has and a handler reads the rule, never
// the words.
InFlightDiagnostic idr::refuse(Location loc, Rule rule) {
  InFlightDiagnostic diagnostic = mlir::emitError(loc);
  if (Diagnostic *underlying = diagnostic.getUnderlyingDiagnostic())
    underlying->getMetadata().push_back(
        DiagnosticArgument(RuleAttr::get(loc->getContext(), rule)));
  diagnostic << refusalHead(rule);
  return diagnostic;
}

InFlightDiagnostic idr::refuse(Operation *op, Rule rule) { return refuse(op->getLoc(), rule); }

std::optional<Rule> idr::refusalRule(Diagnostic &diagnostic) {
  for (DiagnosticArgument &argument : diagnostic.getMetadata())
    if (argument.getKind() == DiagnosticArgument::DiagnosticArgumentKind::Attribute)
      if (auto rule = dyn_cast<RuleAttr>(argument.getAsAttribute()))
        return rule.getValue();
  return std::nullopt;
}
