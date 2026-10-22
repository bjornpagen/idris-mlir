// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What each typed rule reads off one value's type, one predicate per
// condition of the specification: the grade's uses and hold, the family's
// promise and kind, the carrier's buffer semantics; and what each pair rule
// reads off an operand's type and a result's together, their layouts.
// Every fact is the types' own, computed when the type was made; none
// follows a producer or a use.

#include "idr/IR/Effects/Vocabulary.h"

#include "idr/IR/Families/Families.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/BuiltinTypes.h"

using namespace mlir;

namespace idr::effects {

namespace {

// What a value's family says of its member: its kind and its promise, if
// its carrier is a data type.
template <class Ask>
bool ofMember(Type type, Ask &&ask) {
  auto data = dyn_cast<DataType>(unrestricted(type));
  return data && ask(data.getGroup(), data.getMember());
}

bool memoCell(Type type) {
  return ofMember(type, [](FamilyAttr group, uint32_t member) {
    return group.memberKind(member) == MemberKind::Memo;
  });
}

bool rebuiltInPlace(Type type) {
  return ofMember(type, [](FamilyAttr group, uint32_t member) {
    return group.promise(member) == Promise::InPlace;
  });
}

} // namespace

// Used once and freed by its count: the holder's one reference.
template <>
bool holds<Condition::OwnsCount>(Type type) {
  return isLinear(type) && freedBy(type, Release::Counted);
}

// Used once, of a family rebuilt in place, or an unforced memo cell.
template <>
bool holds<Condition::HasIdentity>(Type type) {
  return isLinear(type) || rebuiltInPlace(type) || memoCell(type);
}

// A memo cell's value.
template <>
bool holds<Condition::MemoCell>(Type type) {
  return memoCell(type);
}

// Freed by its count, claiming nothing of its sharing.
template <>
bool holds<Condition::MayBeShared>(Type type) {
  return freedBy(type, Release::Counted) && !claims(type, Unique::Self);
}

// A reuse token claiming everything it reaches unshared, which a token
// holding its cell is and a token that may be null is not.
template <>
bool holds<Condition::HoldsItsCell>(Type type) {
  return claims(type, Unique::Deep);
}

// No family holds a foreign cell yet: the first comes with Rust's runtime,
// whose families will say so when they are made.
template <>
bool holds<Condition::ReachesForeign>(Type) {
  return false;
}

// Memory written in place: a buffer, whatever its grade. A tensor is a
// value, with no memory of its own to read or write.
template <>
bool holds<Condition::Buffer>(Type type) {
  return isa<BaseMemRefType>(unrestricted(type));
}

// Not the same words at run time, as the layout facts each type stored
// when it was made say: the one answer a reindex's tail position, its
// speculation and its lowering read too, so no reader decides it its own
// way.
template <>
bool relates<PairCondition::LaidOutApart>(Type operand, Type result) {
  return families::layoutMatch(operand, result) == LayoutMatch::OtherLayout;
}

} // namespace idr::effects
