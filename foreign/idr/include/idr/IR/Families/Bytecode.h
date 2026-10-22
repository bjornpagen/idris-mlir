// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The parts every one of the families' bytecode codecs writes, in the
// order the frontend's encoders write them: a closed set's case as its
// number, a count before every list, a label as its string, and every type
// and attribute by its entry.
//
//   terms:    count of nodes, then per node its kind and
//             natural, level, successor: the value
//             literal: the constant
//             constructor: the group (absent for its own), member, tag,
//                          arity
//             opaque: nothing
//   sorts:    count, then per sort its kind and
//             scalar: the type; family: the group (absent for its own),
//             member
//
// A member's own layout is its codec's (lib/IR/Families/MemberBytecode.cpp),
// built of these.
#ifndef IDR_IR_FAMILIES_BYTECODE_H
#define IDR_IR_FAMILIES_BYTECODE_H

#include "idr/IR/Families/Terms.h"
#include "idr/Support/Enum.h"

#include "mlir/Bytecode/BytecodeImplementation.h"
#include "mlir/IR/BuiltinAttributes.h"

#include <cstdint>

namespace idr::families::bytecode {

// A case of one of the families' closed sets, written as its number; a
// number that is no case is refused.
template <Enumerated E>
mlir::LogicalResult readCase(mlir::DialectBytecodeReader &reader, E &out) {
  uint64_t value;
  if (mlir::failed(reader.readVarInt(value)))
    return mlir::failure();
  if (value >= EnumTraits<E>::count)
    return reader.emitError() << "expects one of " << EnumTraits<E>::count << " cases, got "
                              << value;
  out = static_cast<E>(value);
  return mlir::success();
}

template <Enumerated E>
void writeCase(mlir::DialectBytecodeWriter &writer, E value) {
  writer.writeVarInt(static_cast<uint64_t>(value));
}

// A count that fits 32 bits.
mlir::LogicalResult readWord32(mlir::DialectBytecodeReader &reader, uint32_t &out);
// A label, as its string.
mlir::LogicalResult readLabel(mlir::DialectBytecodeReader &reader, mlir::StringAttr &out);

// Whole terms, one after the other, appended to `nodes`.
mlir::LogicalResult readNodes(mlir::DialectBytecodeReader &reader,
                              llvm::SmallVectorImpl<TermNode> &nodes);
void writeNodes(mlir::DialectBytecodeWriter &writer, llvm::ArrayRef<TermNode> nodes);

mlir::LogicalResult readSortList(mlir::DialectBytecodeReader &reader,
                                 llvm::SmallVectorImpl<Sort> &sorts);
void writeSortList(mlir::DialectBytecodeWriter &writer, llvm::ArrayRef<Sort> sorts);

} // namespace idr::families::bytecode

#endif // IDR_IR_FAMILIES_BYTECODE_H
