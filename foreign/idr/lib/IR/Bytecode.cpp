// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The idr dialect's bytecode: the readers and writers mlir-tblgen generates
// from the printed records (Generated/IdrBytecode.td), every type and
// attribute of the dialect native, its layout derived from its parameters,
// behind the dialect's bytecode interface as builtin's are. No `idr` text
// crosses the handoff.

#include "idr/IR/IdrDialect.h"

#include "mlir/Bytecode/BytecodeImplementation.h"
#include "llvm/Support/MathExtras.h"
#include "llvm/Support/TypeName.h"

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
