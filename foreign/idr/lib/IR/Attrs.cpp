// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The checks of the dialect's attributes beyond their syntax: a big has one
// width, and an instance key is text. And refusals: the one place their
// words are written, with the rule carried as data in the diagnostic.

#include "idr/IR/IdrDialect.h"

using namespace mlir;
using namespace idr;

// One width per integer, its fewest signed bits, so that equal bigs are
// equal attributes.
LogicalResult BigAttr::verify(function_ref<InFlightDiagnostic()> emitError, APInt value, Type) {
  if (value.getBitWidth() != value.getSignificantBits())
    return emitError() << "expects a big at its fewest signed bits, "
                       << value.getSignificantBits() << ", got " << value.getBitWidth();
  return success();
}

// Every argument is the text the frontend prints for a type, an
// implementation or a shape: the key names, and refers to no symbol, so it
// keeps nothing alive and follows no rename.
LogicalResult InstanceAttr::verify(function_ref<InFlightDiagnostic()> emitError,
                                   StringAttr, ArrayAttr arguments) {
  if (!llvm::all_of(arguments, llvm::IsaPred<StringAttr>))
    return emitError() << "expects every argument of #idr.instance to be a string";
  return success();
}

std::string idr::refusalHead(Rule rule) {
  return ("unsupported (" + stringifyRule(rule) + ")").str();
}

// The rule rides in the diagnostic's metadata, which no handler prints, so
// the message reads as it always has and a handler reads the rule, never
// the words.
InFlightDiagnostic idr::refuse(Location loc, Rule rule) {
  InFlightDiagnostic diagnostic = mlir::emitError(loc);
  if (Diagnostic *underlying = diagnostic.getUnderlyingDiagnostic())
    underlying->getMetadata().push_back(
        DiagnosticArgument(RuleAttr::get(loc->getContext(), rule)));
  diagnostic << refusalHead(rule) << ": ";
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
