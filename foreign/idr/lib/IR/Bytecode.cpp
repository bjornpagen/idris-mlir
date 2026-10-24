// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The idr dialect's bytecode: the readers and writers mlir-tblgen generates
// from the printed records (Generated/IdrBytecode.td), every type and
// attribute of the dialect native, its layout derived from its parameters,
// behind the dialect's bytecode interface as builtin's are, with the codecs
// those records name for an enum, a case held in a class or none, an
// integer of any size, and a value a wire of the specification lays out
// (Generated/Wire.cpp.inc, printed from the wire, as the frontend's encoder
// of it is). Beside the codec of a wired value spelled by its members
// alone, the termination proof, that file prints its text parser, printer
// and hash, hooks the printed ODS names, so this unit defines those too.
// No `idr` text crosses the handoff.

#include "idr/IR/IdrDialect.h"
#include "idr/Support/Enum.h"
#include "idr/Support/Match.h"

#include "mlir/Bytecode/BytecodeImplementation.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/Support/Allocator.h"
#include "llvm/Support/MathExtras.h"
#include "llvm/Support/TypeName.h"

#include <concepts>
#include <cstdint>
#include <memory>
#include <optional>
#include <type_traits>
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

// An array a wired parameter's reader read, with the arena that keeps every
// array its values view: the reader declares one where the builder it gives
// the array to can see it, so what the values view lives until the storage
// that builder makes has copied it.
template <class T>
struct Kept {
  llvm::BumpPtrAllocator arena;
  llvm::SmallVector<T> items;

  operator llvm::ArrayRef<T>() const { return items; }
};

// `values` copied into `arena`, which outlives the vector they were read
// into. Every value a wire lays out is plain data (handles, numbers, views),
// so nothing is destroyed with the arena.
template <class T>
llvm::ArrayRef<T> keep(llvm::BumpPtrAllocator &arena, llvm::ArrayRef<T> values) {
  static_assert(std::is_trivially_destructible_v<T>, "the arena destroys nothing it keeps");
  T *out = arena.Allocate<T>(values.size());
  std::uninitialized_copy(values.begin(), values.end(), out);
  return {out, values.size()};
}

// A case of a closed set of ours, written as its position; a number that is
// no case is refused here, so no value holds one.
template <Enumerated E>
LogicalResult readCase(DialectBytecodeReader &reader, E &result) {
  uint64_t value;
  if (failed(reader.readVarInt(value)))
    return failure();
  if (value >= EnumTraits<E>::count)
    return reader.emitError() << "expects a case of " << llvm::getTypeName<E>() << ", got "
                              << value;
  result = static_cast<E>(value);
  return success();
}

template <Enumerated E>
void writeCase(DialectBytecodeWriter &writer, E value) {
  writer.writeVarInt(static_cast<uint64_t>(std::to_underlying(value)));
}

// A number a wire holds in 32 bits; a wider one is refused here.
LogicalResult readWord32(DialectBytecodeReader &reader, uint32_t &result) {
  uint64_t value;
  if (failed(reader.readVarInt(value)))
    return failure();
  if (!llvm::isUInt<32>(value))
    return reader.emitError() << "expects a number of 32 bits, got " << value;
  result = static_cast<uint32_t>(value);
  return success();
}

// A label, written as its string and held uniqued.
LogicalResult readLabel(DialectBytecodeReader &reader, StringAttr &result) {
  StringRef text;
  if (failed(reader.readString(text)))
    return failure();
  result = StringAttr::get(reader.getContext(), text);
  return success();
}

#include "idr/IR/Generated/Wire.cpp.inc"
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
