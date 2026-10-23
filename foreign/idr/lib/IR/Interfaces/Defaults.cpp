// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a question interface's method answers where its implementer says
// nothing: the hand functions the specification names as the methods'
// defaults, which the generated hooks declare, in one place.

#include "idr/IR/Families/Terms.h"
#include "idr/IR/IdrDialect.h"

#include <algorithm>

using namespace mlir;

namespace idr {

// An op that takes a lifetime and says nothing of it only names it.
LifetimeUse namesLifetime(Operation *, OpOperand &) { return LifetimeUse::Names; }

// An op with no lifetime rule of its own meets every scope its values'
// lifetimes already satisfy.
LogicalResult acceptsLifetimeUse(Operation *, const OpenLifetimes &) { return success(); }

// The levels an indexed type's terms leave free: one more than the largest
// level any of its runs names.
std::uint32_t freeLevelsOfTerms(Type self) {
  std::uint32_t levels = 0;
  for (ArrayRef<families::TermNode> run : cast<IndexedTypeInterface>(self).getIndexTermRuns())
    levels = std::max(levels, families::freeLevelsOf(run));
  return levels;
}

// A type names a member of the group being declared by position only
// where it says so.
std::optional<std::uint32_t> noPositionalMember(Type) { return std::nullopt; }

// A scope's walk reads every part of a type whose own fact does not hold
// them.
bool scopeHoldsEveryPart(Type) { return true; }

// Two literals of a type are the same value where they are the same
// attribute: a type whose literals are uniqued by value says nothing more.
bool literalsIdentical(Type, Attribute a, Attribute b) { return a == b; }

} // namespace idr
