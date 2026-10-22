// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// `!idr.lifetime`'s kind: its codec in text and in bytecode, the directives
// that write a lifetime type an op's result always has as nothing, and what
// ODS and the passes ask of a lifetime's kind.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Lifetimes.h"

#include "mlir/Bytecode/BytecodeImplementation.h"
#include "mlir/IR/DialectImplementation.h"
#include "llvm/Support/MathExtras.h"

#include <cstdint>
#include <optional>
#include <utility>

using namespace mlir;
using namespace idr;

//===----------------------------------------------------------------------===//
// The kind's codec, and the directives that write a known type as nothing
//===----------------------------------------------------------------------===//

// A case's keyword from the specification's table; a home's site after it.
FailureOr<LifetimeKind> idr::parseLifetimeKind(AsmParser &parser) {
  for (LifetimeKind candidate :
       {LifetimeKind::view(), LifetimeKind::room(), LifetimeKind::cursor()})
    if (succeeded(parser.parseOptionalKeyword(candidate.spelling())))
      return candidate;
  if (succeeded(parser.parseOptionalKeyword(LifetimeKind::home(0).spelling()))) {
    std::uint32_t site;
    if (parser.parseInteger(site))
      return failure();
    return LifetimeKind::home(site);
  }
  return parser.emitError(parser.getCurrentLocation(), "expected a lifetime's kind");
}

void idr::printLifetimeKind(AsmPrinter &printer, LifetimeKind kind) {
  printer << kind.spelling();
  kind.fold([] {}, [] {}, [] {}, [&](std::uint32_t site) { printer << ' ' << site; });
}

// The case's number, then a home's site. A number that is no case, or a
// site past 32 bits, is refused here, so no reader of the type meets one.
LogicalResult idr::readLifetimeKind(DialectBytecodeReader &reader, LifetimeKind &kind) {
  uint64_t number;
  if (failed(reader.readVarInt(number)))
    return failure();
  if (number >= EnumTraits<LifetimeKindCase>::count)
    return reader.emitError() << "expects a lifetime's kind, got " << number;
  switch (static_cast<LifetimeKindCase>(number)) {
  case LifetimeKindCase::View:
    kind = LifetimeKind::view();
    return success();
  case LifetimeKindCase::Room:
    kind = LifetimeKind::room();
    return success();
  case LifetimeKindCase::Cursor:
    kind = LifetimeKind::cursor();
    return success();
  case LifetimeKindCase::Home:
    break;
  }
  uint64_t site;
  if (failed(reader.readVarInt(site)))
    return failure();
  if (!llvm::isUInt<32>(site))
    return reader.emitError() << "expects a home's site, got " << site;
  kind = LifetimeKind::home(static_cast<std::uint32_t>(site));
  return success();
}

void idr::writeLifetimeKind(DialectBytecodeWriter &writer, LifetimeKind kind) {
  writer.writeVarInt(static_cast<uint64_t>(std::to_underlying(kind.kindCase())));
  kind.fold([] {}, [] {}, [] {}, [&](std::uint32_t site) { writer.writeVarInt(site); });
}

namespace idr {

// A loan gives its owner back at the owner's own type, written once.
ParseResult parseSameType(OpAsmParser &, Type &returned, Type owner) {
  returned = owner;
  return success();
}
void printSameType(OpAsmPrinter &, Operation *, Type, Type) {}

// The one view lifetime type and the one room lifetime type, written as
// nothing: activation's and forget's results are views, reserve's a room.
ParseResult parseViewLifetime(OpAsmParser &parser, Type &view) {
  view = LifetimeType::get(parser.getContext(), LifetimeKind::view());
  return success();
}
void printViewLifetime(OpAsmPrinter &, Operation *, Type) {}

ParseResult parseRoomLifetime(OpAsmParser &parser, Type &room) {
  room = LifetimeType::get(parser.getContext(), LifetimeKind::room());
  return success();
}
void printRoomLifetime(OpAsmPrinter &, Operation *, Type) {}

} // namespace idr

//===----------------------------------------------------------------------===//
// What a lifetime's kind says
//===----------------------------------------------------------------------===//

namespace {

std::optional<LifetimeKind> kindOfType(Type type) {
  if (auto lifetime = dyn_cast<LifetimeType>(type))
    return lifetime.getKind();
  return std::nullopt;
}

template <typename Ask>
bool kindIs(Type type, Ask ask) {
  std::optional<LifetimeKind> kind = kindOfType(type);
  return kind && ask(*kind);
}

} // namespace

bool idr::admitsPuts(Type type) {
  return kindIs(type, [](LifetimeKind k) { return k.admitsPuts(); });
}
bool idr::isCursorLifetime(Type type) {
  return kindIs(type, [](LifetimeKind k) { return k.isCursor(); });
}
bool idr::isRoomLifetime(Type type) {
  return kindIs(type, [](LifetimeKind k) { return k.isRoom(); });
}
bool idr::isViewLifetime(Type type) {
  return kindIs(type, [](LifetimeKind k) { return k.isView(); });
}
bool idr::isLifetimeOfCase(Type type, LifetimeKindCase kase) {
  return kindIs(type, [&](LifetimeKind k) { return k.kindCase() == kase; });
}

LifetimeKind idr::lifetimes::kindOf(Value lifetime) {
  return cast<LifetimeType>(lifetime.getType()).getKind();
}

bool idr::lifetimes::passesAs(Type arg, Type param) {
  std::optional<LifetimeKind> a = kindOfType(arg);
  std::optional<LifetimeKind> p = kindOfType(param);
  return a && p && a->passesAs(*p);
}
