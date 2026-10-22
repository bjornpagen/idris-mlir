// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What every reader of a member asks whatever its kind: its constructors,
// over the one view (a memo sum's states after its labels), its index
// sorts, its kind, and its hash, which keys the family whose member it is.

#include "idr/IR/Families/FamilyStorage.h"
#include "idr/Support/Match.h"

using namespace mlir;
using namespace idr;
using namespace idr::families;

namespace idr::families {

llvm::hash_code hash_value(const Member &member) {
  auto ctorHash = [](const CtorDecl &c) {
    return llvm::hash_combine(c.label.getAsOpaquePointer(), llvm::hash_combine_range(c.binders),
                              llvm::hash_combine_range(c.equation),
                              llvm::hash_combine_range(c.fields));
  };
  auto labelHash = [](const LabelDecl &l) {
    return llvm::hash_combine(l.label.getAsOpaquePointer(), l.fn.getAsOpaquePointer(),
                              llvm::hash_combine_range(l.binders),
                              llvm::hash_combine_range(l.equation),
                              llvm::hash_combine_range(l.fields));
  };
  return match(
      member,
      [&](const DataMember &m) {
        llvm::hash_code ctors = llvm::hash_value(m.ctors.size());
        for (const CtorDecl &c : m.ctors)
          ctors = llvm::hash_combine(ctors, ctorHash(c));
        return llvm::hash_combine(0, m.label.getAsOpaquePointer(), m.loc.getAsOpaquePointer(),
                                  static_cast<uint8_t>(m.promise),
                                  llvm::hash_combine_range(m.indices), ctors);
      },
      [&](const ClosuresMember &m) {
        llvm::hash_code labels = llvm::hash_value(m.labels.size());
        for (const LabelDecl &l : m.labels)
          labels = llvm::hash_combine(labels, labelHash(l));
        return llvm::hash_combine(1, m.label.getAsOpaquePointer(),
                                  llvm::hash_combine_range(m.indices), labels);
      },
      [&](const MemoMember &m) {
        llvm::hash_code labels = llvm::hash_value(m.labels.size());
        for (const MemoLabelDecl &l : m.labels)
          labels = llvm::hash_combine(labels, static_cast<uint8_t>(l.mode), labelHash(l.label));
        return llvm::hash_combine(2, m.label.getAsOpaquePointer(),
                                  llvm::hash_combine_range(m.indices), labels,
                                  m.forced.getAsOpaquePointer());
      },
      [&](const FramesMember &m) {
        llvm::hash_code ctors = llvm::hash_value(m.ctors.size());
        for (const CtorDecl &c : m.ctors)
          ctors = llvm::hash_combine(ctors, ctorHash(c));
        return llvm::hash_combine(3, m.label.getAsOpaquePointer(), ctors);
      });
}

} // namespace idr::families

namespace idr::families::storage {

// Any member's constructors, in tag order, over the one view; a memo sum's
// states come from its facts.
SmallVector<CtorView> ctorsOf(const Member &member, ArrayRef<CtorView> states) {
  SmallVector<CtorView> out;
  match(
      member,
      [&](const DataMember &m) {
        for (const CtorDecl &c : m.ctors)
          out.push_back({c.label.getValue(), c.binders, c.equation, c.fields});
      },
      [&](const ClosuresMember &m) {
        for (const LabelDecl &l : m.labels)
          out.push_back({l.label.getValue(), l.binders, l.equation, l.fields});
      },
      [&](const MemoMember &m) {
        for (const MemoLabelDecl &l : m.labels)
          out.push_back({l.label.label.getValue(), l.label.binders, l.label.equation,
                         l.label.fields});
        llvm::append_range(out, states);
      },
      [&](const FramesMember &m) {
        for (const CtorDecl &c : m.ctors)
          out.push_back({c.label.getValue(), c.binders, c.equation, c.fields});
      });
  return out;
}

// A frame stack's one index, the awaited result's row as a natural.
const Sort frameIndex[] = {Sort{SortKind::NatSort, 0, Attribute()}};

ArrayRef<Sort> indicesOf(const Member &member) {
  return match(
      member, [](const FramesMember &) { return ArrayRef<Sort>(frameIndex); },
      [](const OneOf<DataMember, ClosuresMember, MemoMember> auto &m) { return m.indices; });
}

MemberKind memberKindOf(const Member &member) {
  return match(
      member, [](const DataMember &) { return MemberKind::Data; },
      [](const ClosuresMember &) { return MemberKind::Closures; },
      [](const MemoMember &) { return MemberKind::Memo; },
      [](const FramesMember &) { return MemberKind::Frames; });
}

} // namespace idr::families::storage
