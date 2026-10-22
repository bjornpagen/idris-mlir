// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A family's members in bytecode, each of the parts the families' codecs
// share (idr/IR/Families/Bytecode.h):
//
//   members:  count, then per member its kind and
//             data: label, promise, location, index sorts, constructors
//             closures: label, index sorts, labels
//             memo: label, index sorts, (mode, label) per label, forced
//             frames: label, constructors
//   a constructor: label, binder sorts, equation terms, field types
//   a label:       label, function, binder sorts, equation terms, fields
//
// A member views arrays of its own, which no flat vector of members owns,
// so the reader keeps them in a scratch arena and makes the family, checked,
// before it returns: the family copies every array once, and the builder
// that follows finds it made.

#include "idr/IR/Families/Bytecode.h"
#include "idr/IR/Families/FamilyStorage.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Match.h"

using namespace mlir;
using namespace idr;
using namespace idr::families;
using namespace idr::families::bytecode;
using storage::Scratch;

namespace {

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
        failed(reader.readAttribute(data.loc)) ||
        failed(readIndexSorts(reader, scratch, data.indices)) ||
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

FamilyAttr idr::readFamily(DialectBytecodeReader &, MLIRContext *context,
                           ArrayRef<Member> members) {
  return FamilyAttr::get(context, members);
}
