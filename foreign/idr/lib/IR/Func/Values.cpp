// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The hand values a function's attributes hold beside its row: Idris's
// termination proof and a put bound, each in text and in bytecode by the
// hooks the specification declares; and the view of a signature's
// parameters by the part of the record each admits, which every position
// of the record is read through.

#include "idr/IR/Func.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Lifetimes.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/DialectImplementation.h"
#include "llvm/ADT/STLExtras.h"

#include <limits>

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

// The attribute's parameter: `component 3`, `acyclic`.
FailureOr<TerminationProof> idr::parseTerminationProof(AsmParser &parser) {
  if (succeeded(parser.parseOptionalKeyword("acyclic")))
    return TerminationProof(Acyclic{});
  std::uint32_t component = 0;
  if (parser.parseKeyword("component") || parser.parseInteger(component))
    return failure();
  return TerminationProof(InComponent{component});
}

void idr::printTerminationProof(AsmPrinter &printer, TerminationProof proof) {
  idr::match(
      proof, [&](InComponent in) { printer << "component " << in.component; },
      [&](Acyclic) { printer << "acyclic"; });
}

// In bytecode: zero for acyclic, else the component plus one.
LogicalResult idr::readTerminationProof(DialectBytecodeReader &reader, TerminationProof &proof) {
  std::uint64_t word = 0;
  if (failed(reader.readVarInt(word)))
    return failure();
  if (word == 0) {
    proof = Acyclic{};
    return success();
  }
  if (word - 1 > std::numeric_limits<std::uint32_t>::max())
    return reader.emitError() << "termination component " << (word - 1) << " out of range";
  proof = InComponent{static_cast<std::uint32_t>(word - 1)};
  return success();
}

void idr::writeTerminationProof(DialectBytecodeWriter &writer, TerminationProof proof) {
  idr::match(
      proof, [&](InComponent in) { writer.writeVarInt(std::uint64_t{in.component} + 1); },
      [&](Acyclic) { writer.writeVarInt(0); });
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

LogicalResult idr::readPutBound(DialectBytecodeReader &reader, PutBound &bound) {
  std::uint64_t parameter = 0;
  if (failed(reader.readVarInt(parameter)) || failed(reader.readVarInt(bound.bytes)))
    return failure();
  if (parameter > std::numeric_limits<std::uint32_t>::max())
    return reader.emitError() << "put parameter " << parameter << " out of range";
  bound.parameter = static_cast<std::uint32_t>(parameter);
  return success();
}

void idr::writePutBound(DialectBytecodeWriter &writer, PutBound bound) {
  writer.writeVarInt(bound.parameter);
  writer.writeVarInt(bound.bytes);
}

// `<[0: 64, 2: 128]>`.
Attribute PutBoundsAttr::parse(AsmParser &parser, Type) {
  SmallVector<PutBound> bounds;
  auto one = [&]() -> ParseResult {
    PutBound bound{};
    if (parser.parseInteger(bound.parameter) || parser.parseColon() ||
        parser.parseInteger(bound.bytes))
      return failure();
    bounds.push_back(bound);
    return success();
  };
  if (parser.parseLess() ||
      parser.parseCommaSeparatedList(AsmParser::Delimiter::Square, one) || parser.parseGreater())
    return {};
  return PutBoundsAttr::getChecked([&] { return parser.emitError(parser.getNameLoc()); },
                                   parser.getContext(), bounds);
}

void PutBoundsAttr::print(AsmPrinter &printer) const {
  printer << "<[";
  llvm::interleaveComma(getBounds(), printer, [&](const PutBound &bound) {
    printer << bound.parameter << ": " << bound.bytes;
  });
  printer << "]>";
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
