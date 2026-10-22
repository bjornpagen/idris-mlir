// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The families' terms and sorts in bytecode (idr/IR/Families/Bytecode.h
// gives their layout), the codecs of the parameters made of them, and the
// builders the dialect's reader calls once it has read a type's or an
// attribute's parameters. An array is read into the vector that owns it,
// and the storage of what the builder makes copies it, so no reader makes
// an attribute to have somewhere to keep what it read.

#include "idr/IR/Families/Bytecode.h"
#include "idr/IR/Families/Families.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/Bytecode/BytecodeImplementation.h"

using namespace mlir;
using namespace idr;
using namespace idr::families;

//===----------------------------------------------------------------------===//
// The parts
//===----------------------------------------------------------------------===//

LogicalResult bytecode::readWord32(DialectBytecodeReader &reader, uint32_t &out) {
  uint64_t value;
  if (failed(reader.readVarInt(value)))
    return failure();
  if (value > UINT32_MAX)
    return reader.emitError() << "expects a count of 32 bits, got " << value;
  out = static_cast<uint32_t>(value);
  return success();
}

LogicalResult bytecode::readLabel(DialectBytecodeReader &reader, StringAttr &out) {
  StringRef text;
  if (failed(reader.readString(text)))
    return failure();
  out = StringAttr::get(reader.getContext(), text);
  return success();
}

LogicalResult bytecode::readNodes(DialectBytecodeReader &reader,
                                  SmallVectorImpl<TermNode> &nodes) {
  uint64_t count;
  if (failed(reader.readVarInt(count)))
    return failure();
  size_t first = nodes.size();
  for (uint64_t i = 0; i < count; ++i) {
    TermNode node{TermKind::Opaque, 0, 0, 0, Attribute()};
    if (failed(readCase(reader, node.kind)))
      return failure();
    switch (node.kind) {
    case TermKind::Natural:
    case TermKind::Level:
    case TermKind::Successor:
      if (failed(reader.readVarInt(node.value)))
        return failure();
      break;
    case TermKind::Literal:
      if (failed(reader.readAttribute(node.payload)))
        return failure();
      break;
    case TermKind::Constructor: {
      FamilyAttr group;
      if (failed(reader.readOptionalAttribute(group)) || failed(readWord32(reader, node.member)) ||
          failed(reader.readVarInt(node.value)) || failed(readWord32(reader, node.arity)))
        return failure();
      node.payload = group;
      break;
    }
    case TermKind::Opaque:
      break;
    }
    nodes.push_back(node);
  }
  if (!countTerms(ArrayRef<TermNode>(nodes).drop_front(first)))
    return reader.emitError() << "expects whole index terms";
  return success();
}

void bytecode::writeNodes(DialectBytecodeWriter &writer, ArrayRef<TermNode> nodes) {
  writer.writeVarInt(nodes.size());
  for (const TermNode &node : nodes) {
    writeCase(writer, node.kind);
    switch (node.kind) {
    case TermKind::Natural:
    case TermKind::Level:
    case TermKind::Successor:
      writer.writeVarInt(node.value);
      break;
    case TermKind::Literal:
      writer.writeAttribute(node.payload);
      break;
    case TermKind::Constructor:
      writer.writeOptionalAttribute(node.payload);
      writer.writeVarInt(node.member);
      writer.writeVarInt(node.value);
      writer.writeVarInt(node.arity);
      break;
    case TermKind::Opaque:
      break;
    }
  }
}

LogicalResult bytecode::readSortList(DialectBytecodeReader &reader, SmallVectorImpl<Sort> &sorts) {
  return reader.readList(sorts, [&](Sort &sort) -> LogicalResult {
    sort = Sort{SortKind::OpaqueSort, 0, Attribute()};
    if (failed(readCase(reader, sort.kind)))
      return failure();
    switch (sort.kind) {
    case SortKind::NatSort:
    case SortKind::TypeSort:
    case SortKind::OpaqueSort:
      return success();
    case SortKind::ScalarSort: {
      Type scalar;
      if (failed(reader.readType(scalar)))
        return failure();
      sort.payload = TypeAttr::get(scalar);
      return success();
    }
    case SortKind::FamilySort: {
      FamilyAttr group;
      if (failed(reader.readOptionalAttribute(group)) || failed(readWord32(reader, sort.member)))
        return failure();
      sort.payload = group;
      return success();
    }
    }
    return failure();
  });
}

void bytecode::writeSortList(DialectBytecodeWriter &writer, ArrayRef<Sort> sorts) {
  writer.writeList(sorts, [&](const Sort &sort) {
    writeCase(writer, sort.kind);
    switch (sort.kind) {
    case SortKind::NatSort:
    case SortKind::TypeSort:
    case SortKind::OpaqueSort:
      return;
    case SortKind::ScalarSort:
      writer.writeType(cast<TypeAttr>(sort.payload).getValue());
      return;
    case SortKind::FamilySort:
      writer.writeOptionalAttribute(sort.payload);
      writer.writeVarInt(sort.member);
      return;
    }
  });
}

//===----------------------------------------------------------------------===//
// The parameters' codecs
//===----------------------------------------------------------------------===//

LogicalResult idr::readIndexTerms(DialectBytecodeReader &reader, SmallVector<TermNode> &value) {
  return bytecode::readNodes(reader, value);
}

void idr::writeIndexTerms(DialectBytecodeWriter &writer, ArrayRef<TermNode> value) {
  bytecode::writeNodes(writer, value);
}

LogicalResult idr::readSorts(DialectBytecodeReader &reader, SmallVector<Sort> &value) {
  return bytecode::readSortList(reader, value);
}

void idr::writeSorts(DialectBytecodeWriter &writer, ArrayRef<Sort> value) {
  bytecode::writeSortList(writer, value);
}

LogicalResult idr::readRefinement(DialectBytecodeReader &reader, DenseI32ArrayAttr &value) {
  return reader.readOptionalAttribute(value);
}

void idr::writeRefinement(DialectBytecodeWriter &writer, DenseI32ArrayAttr value) {
  writer.writeOptionalAttribute(value);
}

LogicalResult idr::readFamilyRef(DialectBytecodeReader &reader, FamilyAttr &value) {
  return reader.readAttribute(value);
}

void idr::writeFamilyRef(DialectBytecodeWriter &writer, FamilyAttr value) {
  writer.writeAttribute(value);
}

//===----------------------------------------------------------------------===//
// The checked builders
//===----------------------------------------------------------------------===//

DataType idr::readDataType(DialectBytecodeReader &reader, MLIRContext *, FamilyAttr group,
                           uint64_t member, ArrayRef<TermNode> indices,
                           DenseI32ArrayAttr refinement, ArrayRef<TermNode> binders) {
  if (member > UINT32_MAX) {
    reader.emitError() << "expects a member of the family, got " << member;
    return {};
  }
  return DataType::getNormalized([&] { return reader.emitError(); }, group,
                                 static_cast<uint32_t>(member), indices, refinement, binders);
}

SelfType idr::readSelf(DialectBytecodeReader &reader, MLIRContext *context, uint64_t member,
                       ArrayRef<TermNode> indices) {
  if (member > UINT32_MAX) {
    reader.emitError() << "expects a member of the group, got " << member;
    return {};
  }
  return SelfType::get(context, member, indices);
}

IndexBindersAttr idr::readIndexBinders(DialectBytecodeReader &, MLIRContext *context,
                                       ArrayRef<Sort> sorts) {
  return IndexBindersAttr::get(context, sorts);
}

IndexArgsAttr idr::readIndexArgs(DialectBytecodeReader &reader, MLIRContext *context,
                                 ArrayRef<TermNode> terms, uint64_t count) {
  if (countTerms(terms) != count) {
    reader.emitError() << "expects " << count << " whole index terms";
    return {};
  }
  return IndexArgsAttr::get(context, terms, count);
}

EquationAttr idr::readEquation(DialectBytecodeReader &reader, MLIRContext *context,
                               ArrayRef<TermNode> lhs, ArrayRef<TermNode> rhs) {
  if (countTerms(lhs) != 1 || countTerms(rhs) != 1) {
    reader.emitError() << "expects one term on each side of an equation";
    return {};
  }
  return EquationAttr::get(context, lhs, rhs);
}
