// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The families' parameters in bytecode, each written as plain parts in the
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
//   members:  count, then per member its kind and
//             data: label, promise, location, index sorts, constructors
//             closures: label, index sorts, labels
//             memo: label, index sorts, (mode, label) per label, forced
//             frames: label, constructors
//   a constructor: label, binder sorts, equation terms, field types
//   a label:       label, function, binder sorts, equation terms, fields
//
// A reader returns arrays the context owns, as a type's parameters must
// outlive the read: what it reads is checked and uniqued (terms as index
// arguments, sorts as index binders, members as their family) before it
// is returned, so the builder that follows finds it made.

#include "FamilyStorage.h"
#include "idr/IR/Families/Families.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Enum.h"
#include "idr/Support/Match.h"

#include "mlir/Bytecode/BytecodeImplementation.h"

using namespace mlir;
using namespace idr;
using namespace idr::families;

namespace {

// A case of one of the families' closed sets, written as its number.
template <Enumerated E>
LogicalResult readCase(DialectBytecodeReader &reader, E &out) {
  uint64_t value;
  if (failed(reader.readVarInt(value)))
    return failure();
  if (value >= EnumTraits<E>::count)
    return reader.emitError() << "expects one of " << EnumTraits<E>::count << " cases, got "
                              << value;
  out = static_cast<E>(value);
  return success();
}

template <Enumerated E>
void writeCase(DialectBytecodeWriter &writer, E value) {
  writer.writeVarInt(static_cast<uint64_t>(value));
}

LogicalResult readWord32(DialectBytecodeReader &reader, uint32_t &out) {
  uint64_t value;
  if (failed(reader.readVarInt(value)))
    return failure();
  if (value > UINT32_MAX)
    return reader.emitError() << "expects a count of 32 bits, got " << value;
  out = static_cast<uint32_t>(value);
  return success();
}

LogicalResult readLabel(DialectBytecodeReader &reader, StringAttr &out) {
  StringRef text;
  if (failed(reader.readString(text)))
    return failure();
  out = StringAttr::get(reader.getContext(), text);
  return success();
}

using storage::Scratch;

LogicalResult readNodes(DialectBytecodeReader &reader, SmallVectorImpl<TermNode> &nodes) {
  uint64_t count;
  if (failed(reader.readVarInt(count)))
    return failure();
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
  if (!countTerms(nodes))
    return reader.emitError() << "expects whole index terms";
  return success();
}

void writeNodes(DialectBytecodeWriter &writer, ArrayRef<TermNode> nodes) {
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

LogicalResult readSortList(DialectBytecodeReader &reader, SmallVectorImpl<Sort> &sorts) {
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

void writeSortList(DialectBytecodeWriter &writer, ArrayRef<Sort> sorts) {
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

// The parts a constructor and a label share: binder sorts, equation terms
// and field types, each kept in `scratch`.
struct Body {
  ArrayRef<Sort> binders;
  ArrayRef<TermNode> equation;
  ArrayRef<Type> fields;
};

LogicalResult readBody(DialectBytecodeReader &reader, Scratch &scratch, Body &body) {
  SmallVector<Sort> binders;
  SmallVector<TermNode> equation;
  SmallVector<Type> fields;
  if (failed(readSortList(reader, binders)) || failed(readNodes(reader, equation)) ||
      failed(reader.readTypes(fields)))
    return failure();
  body = Body{scratch.keep<Sort>(binders), scratch.keep<TermNode>(equation),
              scratch.keep<Type>(fields)};
  return success();
}

void writeBody(DialectBytecodeWriter &writer, ArrayRef<Sort> binders, ArrayRef<TermNode> equation,
               ArrayRef<Type> fields) {
  writeSortList(writer, binders);
  writeNodes(writer, equation);
  writer.writeTypes(fields);
}

LogicalResult readCtors(DialectBytecodeReader &reader, Scratch &scratch,
                        ArrayRef<CtorDecl> &out) {
  SmallVector<CtorDecl> ctors;
  if (failed(reader.readList(ctors, [&](CtorDecl &ctor) -> LogicalResult {
        Body body;
        if (failed(readLabel(reader, ctor.label)) || failed(readBody(reader, scratch, body)))
          return failure();
        ctor.binders = body.binders;
        ctor.equation = body.equation;
        ctor.fields = body.fields;
        return success();
      })))
    return failure();
  out = scratch.keep<CtorDecl>(ctors);
  return success();
}

void writeCtors(DialectBytecodeWriter &writer, ArrayRef<CtorDecl> ctors) {
  writer.writeList(ctors, [&](const CtorDecl &ctor) {
    writer.writeOwnedString(ctor.label.getValue());
    writeBody(writer, ctor.binders, ctor.equation, ctor.fields);
  });
}

LogicalResult readLabelDecl(DialectBytecodeReader &reader, Scratch &scratch, LabelDecl &label) {
  Body body;
  if (failed(readLabel(reader, label.label)) || failed(reader.readAttribute(label.fn)) ||
      failed(readBody(reader, scratch, body)))
    return failure();
  label.binders = body.binders;
  label.equation = body.equation;
  label.fields = body.fields;
  return success();
}

void writeLabelDecl(DialectBytecodeWriter &writer, const LabelDecl &label) {
  writer.writeOwnedString(label.label.getValue());
  writer.writeAttribute(label.fn);
  writeBody(writer, label.binders, label.equation, label.fields);
}

LogicalResult readIndexSorts(DialectBytecodeReader &reader, Scratch &scratch,
                             ArrayRef<Sort> &out) {
  SmallVector<Sort> sorts;
  if (failed(readSortList(reader, sorts)))
    return failure();
  out = scratch.keep<Sort>(sorts);
  return success();
}

LogicalResult readMember(DialectBytecodeReader &reader, Scratch &scratch, Member &out) {
  MemberKind kind;
  if (failed(readCase(reader, kind)))
    return failure();
  switch (kind) {
  case MemberKind::Data: {
    DataMember data;
    if (failed(readLabel(reader, data.label)) || failed(readCase(reader, data.promise)) ||
        failed(reader.readAttribute(data.loc)) || failed(readIndexSorts(reader, scratch, data.indices)) ||
        failed(readCtors(reader, scratch, data.ctors)))
      return failure();
    out = data;
    return success();
  }
  case MemberKind::Closures: {
    ClosuresMember closures;
    SmallVector<LabelDecl> labels;
    if (failed(readLabel(reader, closures.label)) ||
        failed(readIndexSorts(reader, scratch, closures.indices)) ||
        failed(reader.readList(labels, [&](LabelDecl &label) {
          return readLabelDecl(reader, scratch, label);
        })))
      return failure();
    closures.labels = scratch.keep<LabelDecl>(labels);
    out = closures;
    return success();
  }
  case MemberKind::Memo: {
    MemoMember memo;
    SmallVector<MemoLabelDecl> labels;
    if (failed(readLabel(reader, memo.label)) ||
        failed(readIndexSorts(reader, scratch, memo.indices)) ||
        failed(reader.readList(labels, [&](MemoLabelDecl &label) -> LogicalResult {
          if (failed(readCase(reader, label.mode)))
            return failure();
          return readLabelDecl(reader, scratch, label.label);
        })) ||
        failed(reader.readType(memo.forced)))
      return failure();
    memo.labels = scratch.keep<MemoLabelDecl>(labels);
    out = memo;
    return success();
  }
  case MemberKind::Frames: {
    FramesMember frames;
    if (failed(readLabel(reader, frames.label)) || failed(readCtors(reader, scratch, frames.ctors)))
      return failure();
    out = frames;
    return success();
  }
  }
  return failure();
}

void writeMember(DialectBytecodeWriter &writer, const Member &member) {
  match(
      member,
      [&](const DataMember &data) {
        writeCase(writer, MemberKind::Data);
        writer.writeOwnedString(data.label.getValue());
        writeCase(writer, data.promise);
        writer.writeAttribute(data.loc);
        writeSortList(writer, data.indices);
        writeCtors(writer, data.ctors);
      },
      [&](const ClosuresMember &closures) {
        writeCase(writer, MemberKind::Closures);
        writer.writeOwnedString(closures.label.getValue());
        writeSortList(writer, closures.indices);
        writer.writeList(closures.labels,
                         [&](const LabelDecl &label) { writeLabelDecl(writer, label); });
      },
      [&](const MemoMember &memo) {
        writeCase(writer, MemberKind::Memo);
        writer.writeOwnedString(memo.label.getValue());
        writeSortList(writer, memo.indices);
        writer.writeList(memo.labels, [&](const MemoLabelDecl &label) {
          writeCase(writer, label.mode);
          writeLabelDecl(writer, label.label);
        });
        writer.writeType(memo.forced);
      },
      [&](const FramesMember &frames) {
        writeCase(writer, MemberKind::Frames);
        writer.writeOwnedString(frames.label.getValue());
        writeCtors(writer, frames.ctors);
      });
}

} // namespace

//===----------------------------------------------------------------------===//
// The parameters' codecs
//===----------------------------------------------------------------------===//

LogicalResult idr::readIndexTerms(DialectBytecodeReader &reader, ArrayRef<TermNode> &value) {
  SmallVector<TermNode> nodes;
  if (failed(readNodes(reader, nodes)))
    return failure();
  value = IndexArgsAttr::get(reader.getContext(), nodes, *countTerms(nodes)).getTerms();
  return success();
}

void idr::writeIndexTerms(DialectBytecodeWriter &writer, ArrayRef<TermNode> value) {
  writeNodes(writer, value);
}

LogicalResult idr::readSorts(DialectBytecodeReader &reader, ArrayRef<Sort> &value) {
  SmallVector<Sort> sorts;
  if (failed(readSortList(reader, sorts)))
    return failure();
  value = IndexBindersAttr::get(reader.getContext(), sorts).getSorts();
  return success();
}

void idr::writeSorts(DialectBytecodeWriter &writer, ArrayRef<Sort> value) {
  writeSortList(writer, value);
}

// The family is checked and made here, so what is returned is the
// context's: the builder that follows finds the same family.
LogicalResult idr::readMembers(DialectBytecodeReader &reader, ArrayRef<Member> &value) {
  Scratch scratch;
  SmallVector<Member> members;
  if (failed(reader.readList(members, [&](Member &member) {
        return readMember(reader, scratch, member);
      })))
    return failure();
  FamilyAttr family =
      FamilyAttr::getChecked([&] { return reader.emitError(); }, reader.getContext(), members);
  if (!family)
    return failure();
  value = family.getMembers();
  return success();
}

void idr::writeMembers(DialectBytecodeWriter &writer, ArrayRef<Member> value) {
  writer.writeList(value, [&](const Member &member) { writeMember(writer, member); });
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

FamilyAttr idr::readFamily(DialectBytecodeReader &, MLIRContext *context,
                           ArrayRef<Member> members) {
  return FamilyAttr::get(context, members);
}

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
  return SelfType::get(context, static_cast<uint32_t>(member), indices);
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
