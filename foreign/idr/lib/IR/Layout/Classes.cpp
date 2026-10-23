// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The class rule: inline or in a cell is a function of a data type, computed
// once, when the type is made. A frame stack is a frame stack; a memo sum
// is a cell; a numeral is a number, of a fixed width where its bound is
// closed and fits one, a natural otherwise. At an
// index that names a level or holds anything opaque (class Unknown), a
// member of a group that holds itself is a cell and any other is in place
// over its constructors. At closed indices (class Closed) the application
// unfolds over the constructors its indices leave possible, each field at
// the binders its equation solves: in place unless the unfolding meets an
// application again or passes the shape budget, when it takes its member's
// layout at an unknown index. So `#Vect[3]` of words is three words in
// place, `#Vect[v0]` a cell, `List` a cell, and `T 0` of a family whose
// successor climbs its index stops at the budget. The budget bounds the
// classes and never refuses a program: a spent budget leaves a value in its
// cells. The rule gives the type its words too, the one count of its
// runtime components every reader takes (SlotPlan.h).
//
// Everything here reads the declarations and the storage of types that
// exist already, and writes plain arrays: it runs inside a type's
// construction, where nothing may be made.

#include "idr/IR/Families/Families.h"
#include "idr/IR/Families/Unify.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Layout/SlotPlan.h"

#include "mlir/IR/BuiltinTypes.h"

using namespace mlir;

namespace idr::families {

SmallVector<Tag> possibleAt(FamilyAttr group, uint32_t member, ArrayRef<TermNode> indices) {
  size_t count = group.indices(member).size();
  uint32_t levels = freeLevelsOf(indices);
  SmallVector<Tag> out;
  for (uint32_t t = 0, n = group.tagCount(member); t < n; ++t) {
    CtorView ctor = group.ctor(member, Tag{t});
    Subst subst(levels, static_cast<uint32_t>(ctor.binders.size()), Freedom::Unknown,
                Freedom::Unknown, Opacity::MeetsAnything, group);
    if (unifyAll(subst, indices, ctor.equation, count) == Unified::Consistent)
      out.push_back(Tag{t});
  }
  return out;
}

namespace {

// An application being unfolded: its group, member and closed terms.
struct Application {
  FamilyAttr group;
  uint32_t member;
  SmallVector<TermNode> indices;
};

// What a value of an application gives the value in place that holds it:
// its words, whether they hold a reference, and what they reach.
struct Part {
  SmallVector<SlotWord> words;
  Refs refs;
  Reach reach;
};

// A type's facts while it is being made, its words owned.
struct Laid {
  Class cls;
  Layout layout;
  Refs refs;
  Reach reach;
  std::optional<uint64_t> bound;
  SlotPlan slots;

  Part part() const { return Part{slots.flat(), refs, reach}; }
};

// A cell's pointer: one counted word, the cell's address.
SlotWord cellWord() { return SlotWord{PointerWord{}, layout::Word::Cell}; }

// The layout of `member` at an unknown index: a cell where its group holds
// itself, else in place over every declared constructor, each field the
// words its own type computed (no field names the group).
Laid atUnknown(FamilyAttr group, uint32_t member) {
  if (group.containment() == Containment::HoldsItself)
    return {Class::Unknown, Layout::Cell, Refs::References, Reach::Unbounded, std::nullopt,
            oneWord(cellWord())};
  uint32_t declared = group.tagCount(member);
  SmallVector<Tag> every;
  SmallVector<SmallVector<SmallVector<SlotWord>>> fields;
  for (uint32_t t = 0; t < declared; ++t) {
    every.push_back(Tag{t});
    SmallVector<SmallVector<SlotWord>> &perField = fields.emplace_back();
    for (Type field : group.ctor(member, Tag{t}).fields)
      perField.push_back(layout::slotWordsOf(field));
  }
  return {Class::Unknown, Layout::InPlace, group.refsAtUnknown(member),
          group.reachAtUnknown(member), std::nullopt, inPlace(declared, every, fields)};
}

// The width of a closed numeral whose largest value is `height`.
Layout widthOf(uint64_t height) {
  if (height <= 0xFF)
    return Layout::Word8;
  if (height <= 0xFFFF)
    return Layout::Word16;
  if (height <= 0xFFFFFFFF)
    return Layout::Word32;
  return Layout::Word64;
}

// The largest value of a numeral at closed indices: the depth of its
// descending index, along its successor's own layer, less what its zero
// needs.
uint64_t heightOf(FamilyAttr group, uint32_t member, const Descent &descent,
                  ArrayRef<TermNode> indices) {
  size_t count = group.indices(member).size();
  Term at = termsOf(indices, count)[descent.position];
  uint64_t depth = 0;
  if (!descent.argument) {
    depth = at.kind() == TermKind::Natural ? at.head().value : 0;
  } else {
    Term layer = termsOf(group.ctor(member, descent.successor).equation, count)[descent.position];
    while (at.kind() == TermKind::Constructor && at.head().member == layer.head().member &&
           at.head().value == layer.head().value) {
      ++depth;
      at = at.child(*descent.argument);
    }
  }
  return depth > descent.zeroDepth ? depth - descent.zeroDepth : 0;
}

// The layout a member's kind or shape fixes whatever its constructors hold:
// a frame stack, its top an uncounted word; a memo sum's cell; a number,
// its word. None for a member laid out by its constructors. A frame stack
// grows with the recursion and a memo cell's force writes it, so neither
// bounds what it reaches.
std::optional<Laid> fixedLayout(FamilyAttr group, uint32_t member, ArrayRef<TermNode> indices,
                                Class cls) {
  switch (group.memberKind(member)) {
  case MemberKind::Frames:
    return Laid{cls, Layout::FrameStack, Refs::Words, Reach::Unbounded, std::nullopt,
                oneWord(SlotWord{PointerWord{}, layout::Word::Uncounted})};
  case MemberKind::Memo:
    return Laid{cls, Layout::Cell, Refs::References, Reach::Unbounded, std::nullopt,
                oneWord(cellWord())};
  case MemberKind::Data:
  case MemberKind::Closures:
    break;
  }
  if (group.shape(member) != Shape::Numeral)
    return std::nullopt;
  std::optional<Descent> descent = group.descent(member);
  if (cls == Class::Unknown || !descent)
    return Laid{cls, Layout::Natural, Refs::References, Reach::Unbounded, std::nullopt,
                oneWord(SlotWord{IntegerWord{64}, layout::Word::Big})};
  // The width and the bound are one fact: the type keeps the bound, which
  // a range check reads, beside the width it chose.
  uint64_t height = heightOf(group, member, *descent, indices);
  Layout width = widthOf(height);
  return Laid{cls, width, Refs::Words, Reach::Bounded, height,
              oneWord(SlotWord{IntegerWord{numberBits(width)}, layout::Word::Uncounted})};
}

class Unfolder {
public:
  // The unfolding of `app`, in place over the constructors its indices
  // leave possible, or none when it met an application on its path or
  // passed the budget.
  std::optional<Laid> unfold(const Application &app);

private:
  // What `field`, declared in `app`'s member with the binders `subst`
  // solved, gives; none where the unfolding stops.
  std::optional<Part> field(const Application &app, const Subst &subst, Type field);

  SmallVector<const Application *> path;
  uint32_t spent = 0;
};

std::optional<Laid> Unfolder::unfold(const Application &app) {
  for (const Application *on : path)
    if (on->group == app.group && on->member == app.member &&
        ArrayRef<TermNode>(on->indices) == ArrayRef<TermNode>(app.indices))
      return std::nullopt;
  path.push_back(&app);
  SmallVector<Tag> possible = possibleAt(app.group, app.member, app.indices);
  // The application itself spends one, and its tag one where it has one,
  // so a chain of applications that keep nothing in place (a family whose
  // one constructor climbs its index with no other field) passes the
  // budget as any other does.
  spent += 1 + (possible.size() >= 2 ? 1u : 0u);
  if (spent > static_cast<uint32_t>(shapeBudget)) {
    path.pop_back();
    return std::nullopt;
  }
  Refs refs = Refs::Words;
  Reach reach = Reach::Bounded;
  SmallVector<SmallVector<SmallVector<SlotWord>>> fields;
  size_t count = app.group.indices(app.member).size();
  for (Tag tag : possible) {
    CtorView ctor = app.group.ctor(app.member, tag);
    Subst subst(0, static_cast<uint32_t>(ctor.binders.size()), Freedom::Rigid, Freedom::Unknown,
                Opacity::MeetsAnything, app.group);
    (void)unifyAll(subst, app.indices, ctor.equation, count);
    SmallVector<SmallVector<SlotWord>> &perField = fields.emplace_back();
    for (Type f : ctor.fields) {
      std::optional<Part> part = field(app, subst, f);
      if (!part || spent > static_cast<uint32_t>(shapeBudget)) {
        path.pop_back();
        return std::nullopt;
      }
      if (part->refs == Refs::References)
        refs = Refs::References;
      reach = layout::join(reach, part->reach);
      perField.push_back(std::move(part->words));
    }
  }
  path.pop_back();
  return Laid{Class::Closed, Layout::InPlace, refs, reach, std::nullopt,
              inPlace(app.group.tagCount(app.member), possible, fields)};
}

std::optional<Part> Unfolder::field(const Application &app, const Subst &subst, Type type) {
  Type value = unrestricted(type);
  // A member of the field's group, at the field's index terms instantiated
  // by the binders the equation solved; `declared` what the field's own
  // type gives where those terms are not closed.
  auto member = [&](FamilyAttr group, uint32_t index, ArrayRef<TermNode> terms,
                    Part declared) -> std::optional<Part> {
    Application next{group, index, {}};
    TermWriter write(next.indices);
    Instance instance = Instance::Determined;
    for (Term term : termsOf(terms, group.indices(index).size()))
      if (subst.write(write, term, Side::Constructor, 0) == Instance::Undetermined)
        instance = Instance::Undetermined;
    bool closed = instance == Instance::Determined &&
                  llvm::all_of(termsOf(next.indices, group.indices(index).size()),
                               [](Term term) { return term.isClosed(); });
    if (!closed) {
      spent += static_cast<uint32_t>(declared.words.size());
      return declared;
    }
    if (std::optional<Laid> fixed = fixedLayout(group, index, next.indices, Class::Closed)) {
      Part part = fixed->part();
      spent += static_cast<uint32_t>(part.words.size());
      return part;
    }
    std::optional<Laid> unfolded = unfold(next);
    if (!unfolded)
      return std::nullopt;
    return unfolded->part();
  };
  // Essential, two types, each read in its own context: a member named by
  // position is of the group being unfolded, its declared layout the one
  // that group's member has at unknown indices; a data type names its own
  // group and is laid out by its own slots.
  if (auto self = dyn_cast<SelfType>(value))
    return member(app.group, self.getMember(), self.getIndices(),
                  atUnknown(app.group, self.getMember()).part());
  if (auto data = dyn_cast<DataType>(value))
    return member(data.getGroup(), data.getMember(), data.getIndices(),
                  Part{flatWords(data.slots()),
                       data.holdsReferences() ? Refs::References : Refs::Words,
                       layout::reachOf(data)});
  SmallVector<SlotWord> words = layout::slotWordsOf(type);
  spent += static_cast<uint32_t>(words.size());
  return Part{std::move(words), holdsReferences(value) ? Refs::References : Refs::Words,
              layout::reachOf(value)};
}

} // namespace

LayoutFacts classify(FamilyAttr group, uint32_t member, ArrayRef<TermNode> indices,
                     StorageUniquer::StorageAllocator &allocator) {
  auto keep = [&](const Laid &laid) {
    return LayoutFacts{laid.cls,   laid.layout, laid.refs,
                       laid.reach, laid.bound,  laid.slots.keep(allocator)};
  };
  size_t count = group.indices(member).size();
  bool closed = llvm::all_of(termsOf(indices, count), [](Term term) { return term.isClosed(); });
  Class cls = closed ? Class::Closed : Class::Unknown;
  if (std::optional<Laid> fixed = fixedLayout(group, member, indices, cls))
    return keep(*fixed);
  if (!closed)
    return keep(atUnknown(group, member));
  Application app{group, member, SmallVector<TermNode>(indices)};
  Unfolder unfolder;
  if (std::optional<Laid> unfolded = unfolder.unfold(app))
    return keep(*unfolded);
  return keep(atUnknown(group, member));
}

} // namespace idr::families
