// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Refusals: the one place their words are written, with the rule carried as
// data in the diagnostic. A rule's category is read from its printed table
// (Generated/Rules.h.inc), never restated.

#include "idr/IR/IdrDialect.h"

#include "idr/IR/Generated/Rules.h.inc"

using namespace mlir;
using namespace idr;

// The two kinds of words a refusal begins with are the problem's: a
// construct this compiler does not compile is named by its rule, and a
// program Idris rejects is refused in Idris's own words alone.
std::string idr::refusalHead(Rule rule) {
  if (categoryOf[rule] == RuleCategory::UserError)
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
