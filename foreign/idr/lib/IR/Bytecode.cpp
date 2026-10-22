// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The idr dialect's bytecode: the readers and writers mlir-tblgen generates
// from the printed records (Generated/IdrBytecode.td), every type and
// attribute of the dialect native, its layout derived from its parameters,
// behind the dialect's bytecode interface as builtin's are, with the codecs
// those records name for an enum, a case held in a class or none, and an
// integer of any size. No `idr` text crosses the handoff.

#include "idr/IR/IdrDialect.h"
#include "idr/Support/Enum.h"

#include "mlir/Bytecode/BytecodeImplementation.h"
#include "llvm/Support/MathExtras.h"
#include "llvm/Support/TypeName.h"

#include <concepts>
#include <optional>
#include <utility>

using namespace mlir;
using namespace idr;

// An enum of the dialect, written as its case's number. A number that is no
// case is refused here, so no reader of the type meets one.
template <typename E>
LogicalResult idr::readEnum(DialectBytecodeReader &reader, E &result,
                            std::optional<E> (*symbolize)(uint32_t)) {
  // Declared with the hooks (Generated/Hooks.h.inc), which the generated
  // reader calls; instantiated here, the one unit that reads.
  uint64_t value;
  if (failed(reader.readVarInt(value)))
    return failure();
  // The ODS numbers its cases in 32 bits: a wider value is no case, and
  // narrowed it could name one.
  std::optional<E> known =
      llvm::isUInt<32>(value) ? symbolize(static_cast<uint32_t>(value)) : std::nullopt;
  if (!known)
    return reader.emitError() << "expects a case of " << llvm::getTypeName<E>() << ", got "
                              << value;
  result = *known;
  return success();
}

namespace idr {

// A class whose values are the cases of a closed set of ours: it gives its
// case and is made from any one, every case being a value.
template <class C>
concept OverCases = requires(const C value) {
  requires Enumerated<decltype(value.kase())>;
  { C::fromCase(value.kase()) } -> std::same_as<C>;
};

// A case held in such a class, or none: zero for none, else one more than
// the case's position. A number past the cases is refused here.
template <OverCases C>
LogicalResult readOptionalCase(DialectBytecodeReader &reader, std::optional<C> &result) {
  using Case = decltype(std::declval<const C &>().kase());
  uint64_t value;
  if (failed(reader.readVarInt(value)))
    return failure();
  if (value == 0) {
    result = std::nullopt;
    return success();
  }
  if (value > EnumTraits<Case>::count)
    return reader.emitError() << "expects a case of " << llvm::getTypeName<Case>()
                              << " or none, got " << value;
  result = C::fromCase(static_cast<Case>(value - 1));
  return success();
}

template <OverCases C>
void writeOptionalCase(DialectBytecodeWriter &writer, std::optional<C> value) {
  writer.writeVarInt(value ? 1 + static_cast<uint64_t>(std::to_underlying(value->kase())) : 0);
}

// An integer of any size: its width, then upstream's integer of that
// width. No width is zero, and none is past what an integer can hold.
static LogicalResult readInteger(DialectBytecodeReader &reader, APInt &result) {
  uint64_t width;
  if (failed(reader.readVarInt(width)))
    return failure();
  if (width == 0 || width > IntegerType::kMaxWidth)
    return reader.emitError() << "expects an integer's width, got " << width;
  FailureOr<APInt> value = reader.readAPIntWithKnownWidth(static_cast<unsigned>(width));
  if (failed(value))
    return failure();
  result = std::move(*value);
  return success();
}

static void writeInteger(DialectBytecodeWriter &writer, const APInt &value) {
  writer.writeVarInt(value.getBitWidth());
  writer.writeAPIntWithKnownWidth(value);
}

} // namespace idr

namespace {

#include "idr/IR/IdrBytecode.cpp.inc"

// The dialect's bytecode interface, as builtin's: the generated readers and
// writers of the printed records.
struct IdrBytecodeInterface final : BytecodeDialectInterface {
  using BytecodeDialectInterface::BytecodeDialectInterface;

  Attribute readAttribute(DialectBytecodeReader &reader) const override {
    return ::readAttribute(getContext(), reader);
  }
  LogicalResult writeAttribute(Attribute attr, DialectBytecodeWriter &writer) const override {
    return ::writeAttribute(attr, writer);
  }
  Type readType(DialectBytecodeReader &reader) const override {
    return ::readType(getContext(), reader);
  }
  LogicalResult writeType(Type type, DialectBytecodeWriter &writer) const override {
    return ::writeType(type, writer);
  }
};

} // namespace

void idr::detail::addBytecodeInterface(IdrDialect &dialect) {
  dialect.addInterfaces<IdrBytecodeInterface>();
}
