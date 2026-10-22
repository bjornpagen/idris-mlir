// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The builders the dialect's bytecode reader calls once the codecs printed
// from the families' wires have read a type's or an attribute's parameters
// (Generated/Wire.cpp.inc): each checks what was read, as the text parser
// does, and makes it in normal form, so no value bytecode gives is one the
// text could not. The arrays read are kept in the reader's arena until the
// storage of what a builder makes copies them.

#include "idr/IR/Families/Families.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/Bytecode/BytecodeImplementation.h"

using namespace mlir;
using namespace idr;
using namespace idr::families;

// A family is checked as it is made: its declaration's rules, which the
// members as read may break.
FamilyAttr idr::readFamily(DialectBytecodeReader &reader, MLIRContext *context,
                           ArrayRef<Member> members) {
  return FamilyAttr::getChecked([&] { return reader.emitError(); }, context, members);
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
