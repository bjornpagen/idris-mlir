// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The index terms a carrier names, by which the family of its key is
// indexed: one index per place a term stands, so a label's equation is the
// terms its own carrier names at the same places, and a value's family and
// its sink's, two carriers one type up to their terms, name as many terms,
// each at the other's place. A family's forced state is the carrier's value
// over those places, so a suspension of a refined value keeps the terms of
// the binders its refinement keeps, as a closure keeps the terms its
// function's binders take.

#include "idr/IR/Families/Families.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Defunctionalize.h"

#include "llvm/ADT/STLExtras.h"

#include <algorithm>
#include <cstddef>
#include <cstdint>

using namespace mlir;

namespace idr::defunctionalize {

// Each index of each data type, then the binders' terms its refinement
// keeps, and a natural's index, through every type the carrier holds, a
// data type's own parts being its family's. A stack, never a recursion:
// the next part is on top, so the parts are met in the order they stand.
IndexTerms indexTermsOf(Type type) {
  IndexTerms out;
  // Every occurrence counts, each a position of its own, so the walk is
  // this stack and not upstream's walker, which meets a type once.
  SmallVector<Type> pending{type};
  while (!pending.empty()) {
    Type next = pending.pop_back_val();
    if (auto keyed = dyn_cast<IndexPositionsTypeInterface>(next)) {
      keyed.appendIndexPositions(out.sorts, out.nodes);
      continue;
    }
    size_t parts = pending.size();
    next.walkImmediateSubElements([](Attribute) {}, [&](Type part) { pending.push_back(part); });
    std::reverse(pending.begin() + static_cast<std::ptrdiff_t>(parts), pending.end());
  }
  return out;
}

// Each place takes the next level, in indexTermsOf's order. A refined data
// type keeps the constructors its refinement leaves, and the binders it
// keeps take levels after its indices'. Each type is rebuilt after its
// parts, in the order they stand, on a stack.
Type overPositions(Type type) {
  std::uint64_t next = 0;
  auto level = [&] {
    return families::TermNode{TermKind::Level, 0, 0, next++, Attribute()};
  };
  struct Frame {
    Type type;
    SmallVector<Attribute> attrs;
    SmallVector<Type> parts, made;
  };
  SmallVector<Frame> stack;
  Type result;
  auto give = [&](Type made) {
    if (stack.empty())
      result = made;
    else
      stack.back().made.push_back(made);
  };
  auto enter = [&](Type part) {
    if (auto keyed = dyn_cast<IndexPositionsTypeInterface>(part))
      return give(keyed.atFreshPositions(level));
    Frame frame{part, {}, {}, {}};
    part.walkImmediateSubElements([&](Attribute attr) { frame.attrs.push_back(attr); },
                                  [&](Type inner) { frame.parts.push_back(inner); });
    stack.push_back(std::move(frame));
  };
  enter(type);
  while (!stack.empty()) {
    if (stack.back().made.size() < stack.back().parts.size()) {
      enter(stack.back().parts[stack.back().made.size()]);
      continue;
    }
    Frame done = stack.pop_back_val();
    give(done.type.replaceImmediateSubElements(done.attrs, done.made));
  }
  return result;
}

} // namespace idr::defunctionalize

namespace idr {

// A data type is keyed by each index of its member, a family sort naming
// its group where the declaration names it by position, then by the
// binders its refinement keeps, each of its binder's sort.
void DataType::appendIndexPositions(SmallVectorImpl<families::Sort> &sorts,
                                    SmallVectorImpl<families::TermNode> &nodes) const {
  auto place = [&](families::Sort sort) {
    if (sort.kind == SortKind::FamilySort && !sort.payload)
      sort.payload = getGroup();
    sorts.push_back(sort);
  };
  llvm::for_each(getGroup().indices(getMember()), place);
  llvm::append_range(nodes, getIndices());
  // Essential, two types: one refined to a constructor whose binders its
  // indices leave open keeps their terms, each of its binder's sort; any
  // other keeps none.
  if (!getBinders().empty())
    llvm::for_each(binderSorts(*singleTag()), place);
  llvm::append_range(nodes, getBinders());
}

// A natural is keyed by its one index.
void NatType::appendIndexPositions(SmallVectorImpl<families::Sort> &sorts,
                                   SmallVectorImpl<families::TermNode> &nodes) const {
  sorts.push_back({SortKind::NatSort, 0, Attribute()});
  llvm::append_range(nodes, getIndex());
}

// Each index takes the next level, then the binders the refinement keeps.
// A refined data type keeps the constructors its refinement leaves.
Type DataType::atFreshPositions(llvm::function_ref<families::TermNode()> next) const {
  SmallVector<families::TermNode> levels;
  for (size_t i = 0, n = getGroup().indices(getMember()).size(); i < n; ++i)
    levels.push_back(next());
  DataType at = DataType::get(getContext(), getGroup(), getMember(), levels);
  // Essential, three types: a refinement is a fact beyond the indices,
  // kept, with the binders' terms it keeps; an unrefined type's
  // constructors are its indices' to leave.
  if (!getRefinement())
    return at;
  const families::TagSet &tags = possibleTags();
  if (getBinders().empty())
    return at.refined(SmallVector<Tag>(tags.begin(), tags.end()));
  SmallVector<families::TermNode> binders;
  for (size_t i = 0, n = binderSorts(tags.front()).size(); i < n; ++i)
    binders.push_back(next());
  return at.refinedTo(tags.front(), binders);
}

Type NatType::atFreshPositions(llvm::function_ref<families::TermNode()> next) const {
  return NatType::get(getContext(), {next()});
}

} // namespace idr
