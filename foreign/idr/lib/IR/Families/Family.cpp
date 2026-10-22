// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The storage of #idr.family: a group's members, which are its identity,
// copied into the context once, and the facts of the group that need no
// index (whether it holds itself, whether its values can reach a closure
// or a suspension, each member's shape and numeral descent, what a member
// holds at an unknown index, the cells a claim on its own cells covers and
// whether one holds a buffer, its labels in order for the parser),
// computed in its construction from the members and the types they name,
// which exist already: nothing is made while they are.

#include "idr/IR/Families/FamilyStorage.h"
#include "idr/IR/Families/Families.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/Support/Match.h"

#include "mlir/IR/AttrTypeSubElements.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;
using namespace idr;
using namespace idr::families;

namespace idr::families::storage {

// The field's value type: what its grade grades. A declaration's field
// carries its uses alone, so its grade is never one of a grade.
Type valueOf(Type field) { return unrestricted(field); }

// Whether `type` names, anywhere in it, a member of the group its
// declaration is in (`!idr.self`): the walk stays out of every data type
// and family, whose own declarations are theirs.
template <typename... Ts>
bool names(Type type) {
  AttrTypeWalker walker;
  walker.addWalk([](FamilyAttr) { return WalkResult::skip(); });
  bool found = false;
  walker.addWalk([&](Type inner) {
    if (isa<DataType>(inner))
      return WalkResult::skip();
    if (isa<Ts...>(inner)) {
      found = true;
      return WalkResult::interrupt();
    }
    return WalkResult::advance();
  });
  walker.walk<WalkOrder::PreOrder>(type);
  return found;
}

} // namespace idr::families::storage

// A data type answers with its family's fact, computed when the family was
// made, so the walk never enters one; a member of the group being made is
// no data type yet and adds nothing, since the group's answer is the union
// over its members.
ClosureReach idr::families::closureReach(Type type) {
  AttrTypeWalker walker;
  walker.addWalk([](FamilyAttr) { return WalkResult::skip(); });
  ClosureReach out = ClosureReach::NoClosure;
  walker.addWalk([&](Type inner) {
    auto data = dyn_cast<DataType>(inner);
    if (data && data.getGroup().closureReach() == ClosureReach::NoClosure)
      return WalkResult::skip();
    if (!data && !isa<FnType, LazyType>(inner))
      return WalkResult::advance();
    out = ClosureReach::ReachesClosure;
    return WalkResult::interrupt();
  });
  walker.walk<WalkOrder::PreOrder>(type);
  return out;
}

using namespace idr::families::storage;

namespace {

using idr::detail::MemberFacts;

ArrayRef<Sort> copySorts(AttributeStorageAllocator &allocator, ArrayRef<Sort> sorts) {
  return allocator.copyInto(sorts);
}

CtorDecl copyCtor(AttributeStorageAllocator &allocator, const CtorDecl &c) {
  return {c.label, copySorts(allocator, c.binders), allocator.copyInto(c.equation),
          allocator.copyInto(c.fields)};
}

LabelDecl copyLabel(AttributeStorageAllocator &allocator, const LabelDecl &l) {
  return {l.label, l.fn, copySorts(allocator, l.binders), allocator.copyInto(l.equation),
          allocator.copyInto(l.fields)};
}

Member copyMember(AttributeStorageAllocator &allocator, const Member &member) {
  return match(
      member,
      [&](const DataMember &m) -> Member {
        SmallVector<CtorDecl> ctors;
        for (const CtorDecl &c : m.ctors)
          ctors.push_back(copyCtor(allocator, c));
        return DataMember{m.label, m.loc, m.promise, copySorts(allocator, m.indices),
                          allocator.copyInto(ArrayRef<CtorDecl>(ctors))};
      },
      [&](const ClosuresMember &m) -> Member {
        SmallVector<LabelDecl> labels;
        for (const LabelDecl &l : m.labels)
          labels.push_back(copyLabel(allocator, l));
        return ClosuresMember{m.label, copySorts(allocator, m.indices),
                              allocator.copyInto(ArrayRef<LabelDecl>(labels))};
      },
      [&](const MemoMember &m) -> Member {
        SmallVector<MemoLabelDecl> labels;
        for (const MemoLabelDecl &l : m.labels)
          labels.push_back({l.mode, copyLabel(allocator, l.label)});
        return MemoMember{m.label, copySorts(allocator, m.indices),
                          allocator.copyInto(ArrayRef<MemoLabelDecl>(labels)), m.forced};
      },
      [&](const FramesMember &m) -> Member {
        SmallVector<CtorDecl> ctors;
        for (const CtorDecl &c : m.ctors)
          ctors.push_back(copyCtor(allocator, c));
        return FramesMember{m.label, allocator.copyInto(ArrayRef<CtorDecl>(ctors))};
      });
}

// The depth of `term` along a numeral's descent: a natural's value, the
// count of a level's successors, or the layers of the successor's own
// constructor along its argument.
uint64_t depthAlong(Term term, const Term &successorTerm, std::optional<uint32_t> argument) {
  if (!argument) {
    if (term.kind() == TermKind::Natural || term.kind() == TermKind::Successor)
      return term.head().value;
    return 0;
  }
  const TermNode &head = successorTerm.head();
  uint64_t depth = 0;
  while (term.kind() == TermKind::Constructor && term.head().payload == head.payload &&
         term.head().member == head.member && term.head().value == head.value) {
    ++depth;
    term = term.child(*argument);
  }
  return depth;
}

// A numeral's descent: the index position where its successor's field is
// one layer below its result, and how deep its zero sits there.
std::optional<Descent> descentOf(const DataMember &m, unsigned zero, unsigned successor) {
  const CtorDecl &z = m.ctors[zero];
  const CtorDecl &s = m.ctors[successor];
  auto self = cast<SelfType>(valueOf(s.fields.front()));
  SmallVector<Term> results = termsOf(s.equation, m.indices.size());
  SmallVector<Term> below = termsOf(self.getIndices(), m.indices.size());
  SmallVector<Term> zeros = termsOf(z.equation, m.indices.size());
  for (unsigned p = 0; p < m.indices.size(); ++p) {
    const Term &result = results[p];
    const Term &field = below[p];
    std::optional<std::optional<uint32_t>> argument;
    if (result.kind() == TermKind::Successor && result.head().value == 1 &&
        field.kind() == TermKind::Level &&
        field.head().value == result.child(0).head().value)
      argument = std::optional<uint32_t>();
    else if (result.kind() == TermKind::Constructor)
      for (auto [index, arg] : llvm::enumerate(result.arguments()))
        if (arg == field)
          argument = static_cast<uint32_t>(index);
    if (!argument)
      continue;
    return Descent{p, *argument, depthAlong(zeros[p], result, *argument), Tag{successor}};
  }
  return std::nullopt;
}

// A data member's shape: two constructors, one with no field; a numeral
// when the other's one field is the member itself, in a group of one; a
// list when the other has two fields, the member itself and an element.
void shapeOf(const DataMember &m, uint32_t self, size_t members, MemberFacts &facts) {
  if (m.ctors.size() != 2)
    return;
  unsigned zero = m.ctors[0].fields.empty() ? 0 : 1;
  unsigned other = 1 - zero;
  if (!m.ctors[zero].fields.empty())
    return;
  ArrayRef<Type> fields = m.ctors[other].fields;
  auto selfAt = [&](Type field) {
    auto named = dyn_cast<SelfType>(valueOf(field));
    return named && named.getMember() == self;
  };
  if (fields.size() == 1 && members == 1 && selfAt(fields[0])) {
    facts.shape = Shape::Numeral;
    facts.descent = descentOf(m, zero, other);
    return;
  }
  if (fields.size() == 2) {
    for (unsigned tail = 0; tail < 2; ++tail)
      if (selfAt(fields[tail]) && !selfAt(fields[1 - tail])) {
        facts.shape = Shape::List;
        facts.list = ListShape{Tag{zero}, Tag{other}, 1 - tail};
        return;
      }
  }
}

} // namespace

idr::detail::FamilyAttrStorage *
idr::detail::FamilyAttrStorage::construct(AttributeStorageAllocator &allocator, const KeyTy &key) {
  SmallVector<Member> members;
  for (const Member &member : key)
    members.push_back(copyMember(allocator, member));
  auto *storage = new (allocator.allocate<FamilyAttrStorage>())
      FamilyAttrStorage(allocator.copyInto(ArrayRef<Member>(members)));

  // Whether a field of any member names the group: then every member lies
  // on the cycle, the group being a strongly connected component.
  for (const Member &member : storage->members)
    for (const CtorView &ctor : ctorsOf(member, {}))
      for (Type field : ctor.fields)
        if (names<SelfType>(field))
          storage->containment = Containment::HoldsItself;

  SmallVector<MemberFacts> facts;
  for (auto [index, member] : llvm::enumerate(storage->members)) {
    MemberFacts &f = facts.emplace_back();
    ArrayRef<Sort> indices = indicesOf(member);
    f.indices = indices;
    match(
        member,
        [&](const DataMember &data) {
          shapeOf(data, static_cast<uint32_t>(index), storage->members.size(), f);
        },
        [](const ClosuresMember &) {},
        [](const FramesMember &) {},
        [&](const MemoMember &memo) {
          // A memo sum's states bind its indices as their own levels:
          // possible at every application, `forced` holding the value its
          // declaration types.
          SmallVector<TermNode> levels;
          TermWriter write(levels);
          for (uint32_t level = 0; level < indices.size(); ++level)
            write.level(level);
          ArrayRef<TermNode> equation = allocator.copyInto(ArrayRef<TermNode>(levels));
          ArrayRef<Type> forced = allocator.copyInto(ArrayRef<Type>{memo.forced});
          CtorView states[] = {{memoRunning, indices, equation, {}},
                               {memoForced, indices, equation, forced}};
          f.states = allocator.copyInto(ArrayRef<CtorView>(states));
        });
    SmallVector<CtorView> ctors = ctorsOf(member, f.states);
    SmallVector<Tag> order = llvm::to_vector(
        llvm::map_range(llvm::seq<uint32_t>(0, static_cast<uint32_t>(ctors.size())),
                        [](uint32_t t) { return Tag{t}; }));
    llvm::sort(order, [&](Tag a, Tag b) {
      return ctors[static_cast<uint32_t>(a)].label < ctors[static_cast<uint32_t>(b)].label;
    });
    f.byLabel = allocator.copyInto(ArrayRef<Tag>(order));
    // At an unknown index a memo sum, a member of a group that holds
    // itself and a numeral (a natural there) each hold a reference; any
    // other member holds what its fields hold, each field's own type
    // answering, since none names the group.
    bool holds = memberKindOf(member) == MemberKind::Memo ||
                 (memberKindOf(member) != MemberKind::Frames &&
                  storage->containment == Containment::HoldsItself) ||
                 f.shape == Shape::Numeral;
    // What it reaches is bounded where it holds itself nowhere, is no memo
    // cell, frame stack or natural, and every field's own type bounds it.
    Reach reach = memberKindOf(member) == MemberKind::Memo ||
                          memberKindOf(member) == MemberKind::Frames ||
                          storage->containment == Containment::HoldsItself ||
                          f.shape == Shape::Numeral
                      ? Reach::Unbounded
                      : Reach::Bounded;
    for (const CtorView &ctor : ctors)
      for (Type field : ctor.fields) {
        holds = holds || holdsReferences(valueOf(field));
        reach = layout::join(reach, layout::reachOf(valueOf(field)));
      }
    f.refsAtUnknown = holds ? Refs::References : Refs::Words;
    f.reachAtUnknown = reach;
  }
  // The members whose cells a `unique self` claim covers: the member, then
  // through every field the claim reaches (fieldReach: a field of this
  // group, named by position, or of an in_place family of another group,
  // which exists already) each member it names, through this group's
  // members here and through another group's own answer, which its storage
  // computed when it was made.
  for (auto [index, member] : llvm::enumerate(storage->members)) {
    SmallVector<MemberRef> covered{{Attribute(), static_cast<uint32_t>(index)}};
    for (size_t at = 0; at < covered.size(); ++at) {
      if (covered[at].group)
        continue;
      uint32_t own = covered[at].member;
      for (const CtorView &ctor : ctorsOf(storage->members[own], facts[own].states))
        for (Type field : ctor.fields) {
          SmallVector<MemberRef> reached;
          switch (fieldReach(field)) {
          case FieldReach::OwnFamily:
            reached.push_back(
                {Attribute(), static_cast<uint32_t>(cast<SelfType>(valueOf(field)).getMember())});
            break;
          case FieldReach::InPlaceFamily: {
            auto data = cast<DataType>(valueOf(field));
            for (MemberRef other : data.selfCells())
              reached.push_back(
                  {other.group ? other.group : Attribute(data.getGroup()), other.member});
            break;
          }
          case FieldReach::Other:
            break;
          }
          for (MemberRef next : reached)
            if (!llvm::is_contained(covered, next))
              covered.push_back(next);
        }
    }
    facts[index].selfCells = allocator.copyInto(ArrayRef<MemberRef>(covered));
  }
  // Whether an own cell holds a buffer: a field of a member of this group
  // the claim covers is one, or a member of another group it covers says
  // its own cells hold one, as that group's storage computed.
  for (MemberFacts &f : facts)
    for (MemberRef covered : f.selfCells) {
      if (covered.group) {
        if (cast<FamilyAttr>(covered.group).ownBuffers(covered.member) == Buffers::HoldsBuffer)
          f.buffers = Buffers::HoldsBuffer;
        continue;
      }
      for (const CtorView &ctor :
           ctorsOf(storage->members[covered.member], facts[covered.member].states))
        if (llvm::any_of(ctor.fields, [](Type field) { return isa<MemRefType>(valueOf(field)); }))
          f.buffers = Buffers::HoldsBuffer;
    }
  // Whether a value of the group can reach a closure or a suspension: a
  // field of any member's constructor or state names one, itself or through
  // a family of another group, which answered when it was made.
  for (auto [index, member] : llvm::enumerate(storage->members))
    for (const CtorView &ctor : ctorsOf(member, facts[index].states))
      for (Type field : ctor.fields)
        if (families::closureReach(field) == ClosureReach::ReachesClosure)
          storage->closureReach = ClosureReach::ReachesClosure;
  storage->facts = allocator.copyInto(ArrayRef<MemberFacts>(facts));
  return storage;
}

