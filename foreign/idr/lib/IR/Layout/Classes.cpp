// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The class rule: inline or in a cell is a function of a data type, computed
// once, when the type is made. A frame stack is a frame stack; a memo sum
// and a frame stack's answer are cells; a numeral is a number, of a fixed
// width where its bound is closed and fits one, a natural otherwise. At an
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
// cells.
//
// Everything here reads the declarations and the storage of types that
// exist already, and writes plain arrays: it runs inside a type's
// construction, where nothing may be made.

#include "idr/IR/Families/Families.h"
#include "idr/IR/Families/Unify.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"

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

// What an application's unfolding gave: its components, references and
// reach, or that it met itself or passed the budget, so its member's layout
// at an unknown index stands.
struct Unfolded {
  uint32_t components;
  Refs refs;
  Reach reach;

  void add(const Unfolded &part) {
    components += part.components;
    if (part.refs == Refs::References)
      refs = Refs::References;
    reach = layout::join(reach, part.reach);
  }
};

Unfolded unfoldedOf(const LayoutFacts &facts) {
  return Unfolded{facts.components, facts.refs, facts.reach};
}

// The layout of `member` at an unknown index: a cell where its group holds
// itself, else in place over every declared constructor, its fields each
// the layout their own types computed (no field names the group).
LayoutFacts atUnknown(FamilyAttr group, uint32_t member) {
  if (group.containment() == Containment::HoldsItself)
    return {Class::Unknown, Layout::Cell, Refs::References, Reach::Unbounded, 1};
  uint32_t components = group.tagCount(member) >= 2 ? 1 : 0;
  for (uint32_t t = 0, n = group.tagCount(member); t < n; ++t) {
    CtorView ctor = group.ctor(member, Tag{t});
    for (Type field : ctor.fields)
      components += layout::componentCount(unrestricted(field));
  }
  return {Class::Unknown, Layout::InPlace, group.refsAtUnknown(member),
          group.reachAtUnknown(member), components};
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
// a frame stack; a memo sum's cell; a frame stack's answer, written through
// its base frame's destination into a cell its activation holds; a number.
// None for a member laid out by its constructors. A frame stack grows with
// the recursion and a memo cell's force writes it, so neither bounds what
// it reaches; a frame stack's answer is taken as unbounded, as what it
// holds is the program's.
std::optional<LayoutFacts> fixedLayout(FamilyAttr group, uint32_t member,
                                       ArrayRef<TermNode> indices, Class cls) {
  switch (group.memberKind(member)) {
  case MemberKind::Frames:
    return LayoutFacts{cls, Layout::FrameStack, Refs::Words, Reach::Unbounded, 1};
  case MemberKind::Memo:
    return LayoutFacts{cls, Layout::Cell, Refs::References, Reach::Unbounded, 1};
  case MemberKind::Data:
    if (group.holdsFrames())
      return LayoutFacts{cls, Layout::Cell, Refs::References, Reach::Unbounded, 1};
    break;
  case MemberKind::Closures:
    break;
  }
  if (group.shape(member) != Shape::Numeral)
    return std::nullopt;
  std::optional<Descent> descent = group.descent(member);
  if (cls == Class::Unknown || !descent)
    return LayoutFacts{cls, Layout::Natural, Refs::References, Reach::Unbounded, 1};
  return LayoutFacts{cls, widthOf(heightOf(group, member, *descent, indices)), Refs::Words,
                     Reach::Bounded, 1};
}

class Unfolder {
public:
  // The unfolding of `app`, or none when it met an application on its
  // path or passed the budget.
  std::optional<Unfolded> unfold(const Application &app);

private:
  // The components of `field`, declared in `app`'s member with the binders
  // `subst` solved; none where the unfolding stops.
  std::optional<Unfolded> field(const Application &app, const Subst &subst, Type field);

  SmallVector<const Application *> path;
  uint32_t spent = 0;
};

std::optional<Unfolded> Unfolder::unfold(const Application &app) {
  for (const Application *on : path)
    if (on->group == app.group && on->member == app.member &&
        ArrayRef<TermNode>(on->indices) == ArrayRef<TermNode>(app.indices))
      return std::nullopt;
  path.push_back(&app);
  SmallVector<Tag> possible = possibleAt(app.group, app.member, app.indices);
  Unfolded out{possible.size() >= 2 ? 1u : 0u, Refs::Words, Reach::Bounded};
  // The application itself spends one, so a chain of applications that
  // keep nothing in place (a family whose one constructor climbs its index
  // with no other field) passes the budget as any other does.
  spent += 1 + out.components;
  if (spent > static_cast<uint32_t>(shapeBudget)) {
    path.pop_back();
    return std::nullopt;
  }
  size_t count = app.group.indices(app.member).size();
  for (Tag tag : possible) {
    CtorView ctor = app.group.ctor(app.member, tag);
    Subst subst(0, static_cast<uint32_t>(ctor.binders.size()), Freedom::Rigid, Freedom::Unknown,
                Opacity::MeetsAnything, app.group);
    (void)unifyAll(subst, app.indices, ctor.equation, count);
    for (Type f : ctor.fields) {
      std::optional<Unfolded> part = field(app, subst, f);
      if (!part || spent > static_cast<uint32_t>(shapeBudget)) {
        path.pop_back();
        return std::nullopt;
      }
      out.add(*part);
    }
  }
  path.pop_back();
  return out;
}

std::optional<Unfolded> Unfolder::field(const Application &app, const Subst &subst, Type type) {
  Type value = unrestricted(type);
  // A member of the field's group, at the field's index terms instantiated
  // by the binders the equation solved.
  auto member = [&](FamilyAttr group, uint32_t index, ArrayRef<TermNode> terms,
                    LayoutFacts declared) -> std::optional<Unfolded> {
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
      spent += declared.components;
      return unfoldedOf(declared);
    }
    if (std::optional<LayoutFacts> fixed =
            fixedLayout(group, index, next.indices, Class::Closed)) {
      spent += fixed->components;
      return unfoldedOf(*fixed);
    }
    return unfold(next);
  };
  if (auto self = dyn_cast<SelfType>(value))
    return member(app.group, self.getMember(), self.getIndices(),
                  atUnknown(app.group, self.getMember()));
  if (auto data = dyn_cast<DataType>(value))
    return member(data.getGroup(), data.getMember(), data.getIndices(),
                  LayoutFacts{data.cls(), data.layout(),
                              data.holdsReferences() ? Refs::References : Refs::Words,
                              layout::reachOf(data), layout::componentCount(data)});
  uint32_t components = layout::componentCount(value);
  spent += components;
  return Unfolded{components, holdsReferences(value) ? Refs::References : Refs::Words,
                  layout::reachOf(value)};
}

} // namespace

LayoutFacts classify(FamilyAttr group, uint32_t member, ArrayRef<TermNode> indices) {
  size_t count = group.indices(member).size();
  bool closed = llvm::all_of(termsOf(indices, count), [](Term term) { return term.isClosed(); });
  Class cls = closed ? Class::Closed : Class::Unknown;
  if (std::optional<LayoutFacts> fixed = fixedLayout(group, member, indices, cls))
    return *fixed;
  if (!closed)
    return atUnknown(group, member);
  Application app{group, member, SmallVector<TermNode>(indices)};
  Unfolder unfolder;
  if (std::optional<Unfolded> unfolded = unfolder.unfold(app))
    return {Class::Closed, Layout::InPlace, unfolded->refs, unfolded->reach,
            unfolded->components};
  return atUnknown(group, member);
}

} // namespace idr::families
