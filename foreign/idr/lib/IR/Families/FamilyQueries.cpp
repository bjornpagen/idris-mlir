// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a reader asks of a family, over the one view of a constructor and
// the facts its storage derived when it was made.

#include "idr/IR/Families/FamilyStorage.h"
#include "idr/Support/Match.h"

using namespace mlir;
using namespace idr;
using namespace idr::families;
using namespace idr::families::storage;

//===----------------------------------------------------------------------===//
// What a reader asks of a group
//===----------------------------------------------------------------------===//

ArrayRef<Member> FamilyAttr::getMembers() const { return getImpl()->members; }

Containment FamilyAttr::containment() const { return getImpl()->containment; }

MemberKind FamilyAttr::memberKind(uint32_t member) const {
  return memberKindOf(getMembers()[member]);
}

ArrayRef<Sort> FamilyAttr::indices(uint32_t member) const {
  return getImpl()->facts[member].indices;
}

StringAttr FamilyAttr::label(uint32_t member) const {
  return match(getMembers()[member], [](const auto &m) { return m.label; });
}

uint32_t FamilyAttr::tagCount(uint32_t member) const {
  return static_cast<uint32_t>(getImpl()->facts[member].byLabel.size());
}

CtorView FamilyAttr::ctor(uint32_t member, Tag tag) const {
  auto position = static_cast<uint32_t>(tag);
  const idr::detail::MemberFacts &f = getImpl()->facts[member];
  return match(
      getMembers()[member],
      [&](const DataMember &m) -> CtorView {
        const CtorDecl &c = m.ctors[position];
        return {c.label.getValue(), c.binders, c.equation, c.fields};
      },
      [&](const ClosuresMember &m) -> CtorView {
        const LabelDecl &l = m.labels[position];
        return {l.label.getValue(), l.binders, l.equation, l.fields};
      },
      [&](const MemoMember &m) -> CtorView {
        if (position >= m.labels.size())
          return f.states[position - m.labels.size()];
        const LabelDecl &l = m.labels[position].label;
        return {l.label.getValue(), l.binders, l.equation, l.fields};
      },
      [&](const FramesMember &m) -> CtorView {
        const CtorDecl &c = m.ctors[position];
        return {c.label.getValue(), c.binders, c.equation, c.fields};
      });
}

std::optional<Tag> FamilyAttr::tagOf(uint32_t member, StringRef label) const {
  ArrayRef<Tag> byLabel = getImpl()->facts[member].byLabel;
  const Tag *it = llvm::partition_point(
      byLabel, [&](Tag tag) { return ctor(member, tag).label < label; });
  if (it == byLabel.end() || ctor(member, *it).label != label)
    return std::nullopt;
  return *it;
}

Promise FamilyAttr::promise(uint32_t member) const {
  return match(
      getMembers()[member], [](const DataMember &m) { return m.promise; },
      [](const auto &) { return Promise::None; });
}

Shape FamilyAttr::shape(uint32_t member) const { return getImpl()->facts[member].shape; }

std::optional<Descent> FamilyAttr::descent(uint32_t member) const {
  return getImpl()->facts[member].descent;
}

std::optional<ListShape> FamilyAttr::listShape(uint32_t member) const {
  return getImpl()->facts[member].list;
}

std::optional<MemoView> FamilyAttr::memo(uint32_t member) const {
  return match(
      getMembers()[member],
      [](const MemoMember &m) -> std::optional<MemoView> { return MemoView{m.labels}; },
      [](const auto &) -> std::optional<MemoView> { return std::nullopt; });
}

std::optional<ClosuresView> FamilyAttr::closures(uint32_t member) const {
  return match(
      getMembers()[member],
      [](const ClosuresMember &m) -> std::optional<ClosuresView> { return ClosuresView{m.labels}; },
      [](const auto &) -> std::optional<ClosuresView> { return std::nullopt; });
}

Refs FamilyAttr::refsAtUnknown(uint32_t member) const {
  return getImpl()->facts[member].refsAtUnknown;
}

Reach FamilyAttr::reachAtUnknown(uint32_t member) const {
  return getImpl()->facts[member].reachAtUnknown;
}

Buffers FamilyAttr::ownBuffers(uint32_t member) const { return getImpl()->facts[member].buffers; }

ArrayRef<MemberRef> FamilyAttr::selfCells(uint32_t member) const {
  return getImpl()->facts[member].selfCells;
}

FlatSymbolRefAttr FamilyAttr::labelFunction(uint32_t member, Tag tag) const {
  auto position = static_cast<uint32_t>(tag);
  return match(
      getMembers()[member], [](const DataMember &) { return FlatSymbolRefAttr(); },
      [&](const ClosuresMember &m) { return m.labels[position].fn; },
      [&](const MemoMember &m) {
        return position < m.labels.size() ? m.labels[position].label.fn
                                          : FlatSymbolRefAttr();
      },
      [](const FramesMember &) { return FlatSymbolRefAttr(); });
}

std::optional<Mode> FamilyAttr::labelMode(uint32_t member, Tag tag) const {
  auto position = static_cast<uint32_t>(tag);
  return match(
      getMembers()[member],
      [&](const MemoMember &m) -> std::optional<Mode> {
        if (position >= m.labels.size())
          return std::nullopt;
        return m.labels[position].mode;
      },
      [](const auto &) -> std::optional<Mode> { return std::nullopt; });
}

bool FamilyAttr::namesLabels() const {
  for (const Member &member : getMembers())
    for (const CtorView &ctor : ctorsOf(member, {}))
      for (Type field : ctor.fields)
        if (families::namesLabels(field))
          return true;
  return false;
}
