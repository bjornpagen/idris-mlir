// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The rules of a declaration, checked once per group, when it is made,
// with no context: a group of one member or more, labels that tell its
// members and each member's constructors apart; per constructor, an
// equation of one term per index, each term naming only its binders and of
// its position's sort, every binder occurring somewhere (one that occurs
// nowhere is an erased proof, which is not declared), and fields that are
// field types, graded by their uses alone, but a frame's, which keep their
// values' whole grades. An array field is its buffer,
// never a tensor. Whether a level's binder is of the sort its position
// asks is read here too, since a declaration is its own scope; what a
// value's type may name is the function's scope walk's.

#include "FamilyStorage.h"
#include "idr/IR/Families/Families.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Match.h"

#include "mlir/IR/AttrTypeSubElements.h"
#include "mlir/IR/BuiltinTypes.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;
using namespace idr;
using namespace idr::families;

namespace {

using EmitError = function_ref<InFlightDiagnostic()>;

// The index sorts of member `member` of the group a sort or a term names,
// `own` for a null group; none for a member the group does not have.
std::optional<ArrayRef<Sort>> sortsOfMember(Attribute payload, uint32_t member,
                                            ArrayRef<Member> own) {
  if (!payload) {
    if (member >= own.size())
      return std::nullopt;
    return storage::indicesOf(own[member]);
  }
  auto group = cast<FamilyAttr>(payload);
  if (member >= group.getMembers().size())
    return std::nullopt;
  return group.indices(member);
}

// Whether a binder of sort `binder` may stand where `position` is asked: a
// natural's position takes a natural's binder; a family's, a binder of
// that family member; any other, a binder of the same sort.
bool sortFits(const Sort &binder, const Sort &position) { return binder == position; }

LogicalResult verifyTerm(EmitError emitError, Term term, const Sort &sort,
                         ArrayRef<Sort> binders, ArrayRef<Member> own) {
  const TermNode &head = term.head();
  switch (head.kind) {
  case TermKind::Opaque:
    return success();
  case TermKind::Level:
  case TermKind::Successor: {
    uint64_t level = head.kind == TermKind::Level ? head.value : term.child(0).head().value;
    if (level >= binders.size())
      return emitError() << "names level " << level << " where " << binders.size()
                         << " binders are in scope";
    if (!sortFits(binders[level], sort))
      return emitError() << "names level " << level << " in a position of another sort";
    if (head.kind == TermKind::Successor && sort.kind != SortKind::NatSort)
      return emitError() << "adds to a level of a sort that is no natural";
    return success();
  }
  case TermKind::Natural:
    if (sort.kind != SortKind::NatSort)
      return emitError() << "holds a natural in a position of a sort that is no natural";
    return success();
  case TermKind::Literal:
    if (sort.kind == SortKind::TypeSort && isa<TypeAttr>(head.payload))
      return success();
    if (sort.kind == SortKind::ScalarSort) {
      auto typed = dyn_cast<TypedAttr>(head.payload);
      if (typed && typed.getType() == cast<TypeAttr>(sort.payload).getValue())
        return success();
    }
    return emitError() << "holds the literal " << head.payload << " in a position of another sort";
  case TermKind::Constructor: {
    if (sort.kind != SortKind::FamilySort || sort.member != head.member ||
        sort.payload != head.payload)
      return emitError() << "holds a constructor of another family than its position's";
    return success();
  }
  }
  return success();
}

LogicalResult verifyEquation(EmitError emitError, StringRef label, ArrayRef<TermNode> equation,
                             ArrayRef<Sort> indices, ArrayRef<Sort> binders, ArrayRef<Member> own) {
  if (countTerms(equation) != indices.size())
    return emitError() << "@" << label << "'s equation does not hold one whole term per index";
  size_t at = 0;
  for (const Sort &sort : indices) {
    Term term(equation.drop_front(at));
    if (failed(verifyTerm([&] { return emitError() << "@" << label << "'s equation "; }, term,
                          sort, binders, own)))
      return failure();
    at += term.nodes().size();
  }
  return success();
}

// The levels a field type names, through the index terms of the types it
// holds, and its own group's members it names, each checked.
// What a field may hold: a field type; and in a frame also what a frame
// keeps of its call, a lifetime and what is used once by its type (a
// package, a reuse token, a destination).
enum class Holder : uint8_t { Constructor, Frame };

bool holds(Holder holder, Type value) {
  return isFieldType(value) ||
         (holder == Holder::Frame && (isLinearByType(value) || isa<LifetimeType>(value)));
}

LogicalResult verifyField(EmitError emitError, StringRef label, Type field,
                          ArrayRef<Sort> binders, ArrayRef<Member> own,
                          llvm::SmallDenseSet<uint64_t> &named, Holder holder) {
  // Essential, two holders: a constructor's field holds what the value it
  // is read from holds, so it is graded by its uses alone; a frame, pushed
  // once and popped once and freeing nothing, keeps each value at its whole
  // grade, its quantity and its claim, and gives it back so.
  Type value = field;
  if (auto graded = dyn_cast<GradedType>(field)) {
    if (holder == Holder::Constructor && (graded.getUses() != Uses::Once || graded.getHold()))
      return emitError() << "@" << label << " has the field " << field
                         << ", graded but by its uses alone, and only to say it is used once";
    value = graded.getCarrier();
  }
  if (!holds(holder, value))
    return emitError() << "@" << label << " has a field of unsupported type " << field;
  if (isa<RankedTensorType>(value))
    return emitError() << "@" << label << " has the tensor field " << field
                       << ": an array field is its buffer";
  LogicalResult result = success();
  auto levels = [&](ArrayRef<TermNode> nodes) {
    for (const TermNode &node : nodes)
      if (node.kind == TermKind::Level) {
        named.insert(node.value);
        if (node.value >= binders.size())
          result = emitError() << "@" << label << " has a field naming level " << node.value
                               << " where " << binders.size() << " binders are in scope";
      }
  };
  // Another group's declaration is its own scope: the walk stays out of it.
  AttrTypeWalker walker;
  walker.addWalk([](FamilyAttr) { return WalkResult::skip(); });
  walker.addWalk([&](Type inner) {
    if (auto data = dyn_cast<DataType>(inner)) {
      levels(data.getIndices());
      levels(data.getBinders());
      return WalkResult::skip();
    }
    if (auto nat = dyn_cast<NatType>(inner))
      levels(nat.getIndex());
    else if (auto self = dyn_cast<SelfType>(inner)) {
      levels(self.getIndices());
      std::optional<ArrayRef<Sort>> sorts = sortsOfMember(Attribute(), self.getMember(), own);
      if (!sorts)
        result = emitError() << "@" << label << " names member " << self.getMember()
                             << " of a group of " << own.size();
      else if (countTerms(self.getIndices()) != sorts->size() ||
               freeLevelsOf(self.getIndices()) > binders.size())
        result = emitError() << "@" << label << " names its group's member with indices that "
                             << "do not fit it";
    }
    return WalkResult::advance();
  });
  walker.walk<WalkOrder::PreOrder>(field);
  return result;
}

// What every constructor and label checks: its equation, its binders'
// sorts, its fields, and that each binder occurs somewhere.
LogicalResult verifyCtor(EmitError emitError, StringRef label, ArrayRef<Sort> binders,
                         ArrayRef<TermNode> equation, ArrayRef<Type> fields,
                         ArrayRef<Sort> indices, ArrayRef<Member> own,
                         Holder holder = Holder::Constructor) {
  if (failed(verifyEquation(emitError, label, equation, indices, binders, own)))
    return failure();
  for (const Sort &sort : binders)
    if (sort.kind == SortKind::FamilySort && !sortsOfMember(sort.payload, sort.member, own))
      return emitError() << "@" << label << " binds a member its group does not have";
  llvm::SmallDenseSet<uint64_t> named;
  for (const TermNode &node : equation)
    if (node.kind == TermKind::Level)
      named.insert(node.value);
  for (Type field : fields)
    if (failed(verifyField(emitError, label, field, binders, own, named, holder)))
      return failure();
  for (uint64_t level = 0; level < binders.size(); ++level)
    if (!named.contains(level))
      return emitError() << "@" << label << " binds level " << level
                         << ", which occurs nowhere: an erased proof is not declared";
  return success();
}

} // namespace

LogicalResult FamilyAttr::verify(EmitError emitError, ArrayRef<Member> members) {
  if (members.empty())
    return emitError() << "expects a group of one member or more";
  llvm::SmallDenseSet<StringRef> memberLabels;
  for (const Member &member : members) {
    StringRef name = match(member, [](const auto &m) { return m.label.getValue(); });
    if (name.empty() || !memberLabels.insert(name).second)
      return emitError() << "expects members with distinct labels, got \"" << name << "\"";
    ArrayRef<Sort> indices = storage::indicesOf(member);
    for (const Sort &sort : indices)
      if (sort.kind == SortKind::FamilySort && !sortsOfMember(sort.payload, sort.member, members))
        return emitError() << "\"" << name << "\" is indexed by a member its group does not have";
    llvm::SmallDenseSet<StringRef> labels{memoRunning, memoForced};
    auto distinct = [&](StringRef label) -> LogicalResult {
      if (label.empty() || !labels.insert(label).second)
        return emitError() << "\"" << name << "\" has two constructors @" << label
                           << ", or one with a memo state's label";
      return success();
    };
    LogicalResult checked = match(
        member,
        [&](const DataMember &m) -> LogicalResult {
          labels.erase(memoRunning);
          labels.erase(memoForced);
          for (const CtorDecl &c : m.ctors)
            if (failed(distinct(c.label.getValue())) ||
                failed(verifyCtor(emitError, c.label.getValue(), c.binders, c.equation, c.fields,
                                  indices, members)))
              return failure();
          return success();
        },
        [&](const ClosuresMember &m) -> LogicalResult {
          labels.erase(memoRunning);
          labels.erase(memoForced);
          for (const LabelDecl &l : m.labels)
            if (failed(distinct(l.label.getValue())) || !l.fn ||
                failed(verifyCtor(emitError, l.label.getValue(), l.binders, l.equation,
                                  l.fields, indices, members)))
              return failure();
          return success();
        },
        [&](const MemoMember &m) -> LogicalResult {
          for (const MemoLabelDecl &l : m.labels)
            if (failed(distinct(l.label.label.getValue())) || !l.label.fn ||
                failed(verifyCtor(emitError, l.label.label.getValue(), l.label.binders,
                                  l.label.equation, l.label.fields, indices, members)))
              return failure();
          if (!m.forced || !isFieldType(m.forced))
            return emitError() << "\"" << name << "\" forces a value of no field type";
          return success();
        },
        [&](const FramesMember &m) -> LogicalResult {
          labels.erase(memoRunning);
          labels.erase(memoForced);
          for (const CtorDecl &c : m.ctors)
            if (failed(distinct(c.label.getValue())) ||
                failed(verifyCtor(emitError, c.label.getValue(), c.binders, c.equation, c.fields,
                                  indices, members, Holder::Frame)))
              return failure();
          return success();
        });
    if (failed(checked))
      return failure();
  }
  return success();
}
