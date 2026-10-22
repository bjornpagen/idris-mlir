// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The attributes and types a family's declaration holds, as MLIR walks and
// replaces them: every label, location and function, every sort's and
// term's attribute, every field type and a memo's forced type, in one
// order, which one traversal fixes for the walk and the replacement alike.
// A member's arrays nest, so a replacement rebuilds them in a scratch arena
// the new family copies when it is made.

#include "idr/IR/Families/FamilyStorage.h"
#include "idr/IR/Families/Families.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Match.h"

using namespace mlir;
using namespace idr;
using namespace idr::families;
using storage::Scratch;

namespace {

// Visits every attribute and type of members rebuilt in `scratch`, in one
// order: `visit` takes each by reference and may replace it.
template <typename Visit>
class Traversal {
public:
  Traversal(Scratch &scratch, Visit &visit) : scratch(scratch), visit(visit) {}

  void member(Member &member) {
    match(
        member,
        [&](DataMember &data) {
          attr(data.label);
          attr(data.loc);
          sorts(data.indices);
          ctors(data.ctors);
        },
        [&](ClosuresMember &closures) {
          attr(closures.label);
          sorts(closures.indices);
          MutableArrayRef<LabelDecl> labels = scratch.keep(closures.labels);
          for (LabelDecl &decl : labels)
            label(decl);
          closures.labels = labels;
        },
        [&](MemoMember &memo) {
          attr(memo.label);
          sorts(memo.indices);
          MutableArrayRef<MemoLabelDecl> labels = scratch.keep(memo.labels);
          for (MemoLabelDecl &decl : labels)
            label(decl.label);
          memo.labels = labels;
          visit(memo.forced);
        },
        [&](FramesMember &frames) {
          attr(frames.label);
          ctors(frames.ctors);
        });
  }

private:
  // An absent attribute (a family named by position) is no sub-element.
  template <typename A>
  void attr(A &value) {
    if (!value)
      return;
    Attribute held = value;
    visit(held);
    value = cast_if_present<A>(held);
  }

  void sorts(ArrayRef<Sort> &held) {
    MutableArrayRef<Sort> out = scratch.keep(held);
    for (Sort &sort : out)
      if (sort.payload)
        visit(sort.payload);
    held = out;
  }

  void terms(ArrayRef<TermNode> &held) {
    MutableArrayRef<TermNode> out = scratch.keep(held);
    for (TermNode &node : out)
      if (node.payload)
        visit(node.payload);
    held = out;
  }

  void types(ArrayRef<Type> &held) {
    MutableArrayRef<Type> out = scratch.keep(held);
    for (Type &type : out)
      visit(type);
    held = out;
  }

  void ctors(ArrayRef<CtorDecl> &held) {
    MutableArrayRef<CtorDecl> out = scratch.keep(held);
    for (CtorDecl &ctor : out) {
      attr(ctor.label);
      sorts(ctor.binders);
      terms(ctor.equation);
      types(ctor.fields);
    }
    held = out;
  }

  void label(LabelDecl &decl) {
    attr(decl.label);
    attr(decl.fn);
    sorts(decl.binders);
    terms(decl.equation);
    types(decl.fields);
  }

  Scratch &scratch;
  Visit &visit;
};

template <typename Visit>
SmallVector<Member> traverse(FamilyAttr family, Scratch &scratch, Visit &&visit) {
  SmallVector<Member> members(family.getMembers());
  Traversal<std::remove_reference_t<Visit>> traversal(scratch, visit);
  for (Member &member : members)
    traversal.member(member);
  return members;
}

// The two steps stay `function_ref`s: upstream's sub-element walk hands
// them so and keeps this function as its WalkImmediateSubElementsFn, a
// `function_ref` too. Below them the traversal is a template.
void walkFamily(Attribute attr, function_ref<void(Attribute)> walkAttrs,
                function_ref<void(Type)> walkTypes) {
  Scratch scratch;
  traverse(cast<FamilyAttr>(attr), scratch,
           Cases{[&](Attribute &value) { walkAttrs(value); },
                 [&](Type &value) { walkTypes(value); }});
}

// The replacements arrive in the walk's order, so the same traversal takes
// them one by one.
Attribute replaceFamily(Attribute attr, ArrayRef<Attribute> attrs, ArrayRef<Type> types) {
  Scratch scratch;
  SmallVector<Member> members =
      traverse(cast<FamilyAttr>(attr), scratch,
               Cases{[&](Attribute &value) {
                       value = attrs.front();
                       attrs = attrs.drop_front();
                     },
                     [&](Type &value) {
                       value = types.front();
                       types = types.drop_front();
                     }});
  return FamilyAttr::get(attr.getContext(), members);
}

} // namespace

AbstractAttribute::WalkImmediateSubElementsFn FamilyAttr::getWalkImmediateSubElementsFn() {
  return walkFamily;
}

AbstractAttribute::ReplaceImmediateSubElementsFn FamilyAttr::getReplaceImmediateSubElementsFn() {
  return replaceFamily;
}
