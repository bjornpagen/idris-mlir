// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The values a function's attributes hold beside its row: the text of
// Idris's termination proof and of the put bounds, by the hooks the
// specification declares (their bytecode is printed from their wires); and
// the view of a signature's parameters by the part of the record each
// admits, which every position of the record is read through.

#include "idr/IR/Func.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Lifetimes.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/DialectImplementation.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;
using namespace idr;

//===----------------------------------------------------------------------===//
// Termination proofs
//===----------------------------------------------------------------------===//

llvm::hash_code idr::hash_value(const TerminationProof &proof) {
  return idr::match(
      proof, [](InComponent in) { return llvm::hash_combine(0u, in.component); },
      [](Acyclic) { return llvm::hash_combine(1u); });
}

// The proof's text, `component 3` or `acyclic`; its bytecode is its wire's.
FailureOr<TerminationProof> idr::parseProof(AsmParser &parser) {
  if (succeeded(parser.parseOptionalKeyword("acyclic")))
    return TerminationProof(Acyclic{});
  std::uint32_t component = 0;
  if (parser.parseKeyword("component") || parser.parseInteger(component))
    return failure();
  return TerminationProof(InComponent{component});
}

void idr::printProof(AsmPrinter &printer, TerminationProof proof) {
  idr::match(
      proof, [&](InComponent in) { printer << "component " << in.component; },
      [&](Acyclic) { printer << "acyclic"; });
}

Termination idr::FuncOp::getTermination() {
  TerminatesAttr proof = getTerminatesAttr();
  if (!proof)
    return Unproved{};
  return idr::match(
      proof.getProof(), [](InComponent in) -> Termination { return in; },
      [](Acyclic acyclic) -> Termination { return acyclic; });
}

//===----------------------------------------------------------------------===//
// Put bounds
//===----------------------------------------------------------------------===//

llvm::hash_code idr::hash_value(const PutBound &bound) {
  return llvm::hash_combine(bound.parameter, bound.bytes);
}

// The bounds' text, `[0: 64, 2: 128]`; their bytecode is their wire's.
FailureOr<SmallVector<PutBound>> idr::parsePutBounds(AsmParser &parser) {
  SmallVector<PutBound> bounds;
  auto one = [&]() -> ParseResult {
    PutBound bound{};
    if (parser.parseInteger(bound.parameter) || parser.parseColon() ||
        parser.parseInteger(bound.bytes))
      return failure();
    bounds.push_back(bound);
    return success();
  };
  if (parser.parseCommaSeparatedList(AsmParser::Delimiter::Square, one))
    return failure();
  return bounds;
}

void idr::printPutBounds(AsmPrinter &printer, ArrayRef<PutBound> bounds) {
  printer << '[';
  llvm::interleaveComma(bounds, printer, [&](const PutBound &bound) {
    printer << bound.parameter << ": " << bound.bytes;
  });
  printer << ']';
}

// Positions increase, each once: a parameter has at most one bound, and the
// record is read in one pass beside the parameters.
LogicalResult PutBoundsAttr::verify(function_ref<InFlightDiagnostic()> emitError,
                                    ArrayRef<PutBound> bounds) {
  for (auto [before, after] : llvm::zip(bounds, bounds.drop_front()))
    if (before.parameter >= after.parameter)
      return emitError() << "lists put parameter " << after.parameter << " after "
                         << before.parameter << ": positions increase, each once";
  return success();
}

//===----------------------------------------------------------------------===//
// The parameters' parts
//===----------------------------------------------------------------------===//

bool idr::admitsWrite(Type type) {
  std::optional<Hold> hold = holdOf(type);
  return hold && hold->release() == Release::Counted && hold->claims(Unique::Self);
}

idr::ParameterParts::ParameterParts(TypeRange parameters) {
  parts.reserve(parameters.size());
  for (Type type : parameters) {
    if (admitsWrite(type))
      parts.push_back(WritePart{writes++});
    else if (admitsPuts(type))
      parts.push_back(PutPart{puts++});
    else
      parts.push_back(NoPart{});
  }
}
