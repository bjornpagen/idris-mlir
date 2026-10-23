// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Index terms over their nodes: their extent, their levels and their
// normal form, a sum of naturals among them. How a term is written is
// TermSyntax.cpp's.

#include "idr/IR/Families/Terms.h"

#include "llvm/ADT/STLExtras.h"

#include <limits>

using namespace mlir;

namespace idr::families {

llvm::hash_code hash_value(const TermNode &node) {
  return llvm::hash_combine(static_cast<uint8_t>(node.kind), node.member, node.arity, node.value,
                            node.payload.getAsOpaquePointer());
}

llvm::hash_code hash_value(const Sort &sort) {
  return llvm::hash_combine(static_cast<uint8_t>(sort.kind), sort.member,
                            sort.payload.getAsOpaquePointer());
}

//===----------------------------------------------------------------------===//
// Extent and levels
//===----------------------------------------------------------------------===//

namespace {

// The nodes that follow `node` as its own: a constructor's arguments, a
// successor's level, a sum's parts, a part's level.
uint64_t owedBy(const TermNode &node) {
  switch (node.kind) {
  case TermKind::Successor:
  case TermKind::Multiple:
    return 1;
  case TermKind::Sum:
  case TermKind::Constructor:
    return node.arity;
  case TermKind::Natural:
  case TermKind::Level:
  case TermKind::Literal:
  case TermKind::Opaque:
    return 0;
  }
  return 0;
}

// Whether the `parts` parts of a sum, each a multiple and then its level,
// start at `nodes[at]` in normal form: levels ascending, each at least
// once, and more than one level once in all.
bool normalParts(ArrayRef<TermNode> nodes, size_t at, uint32_t parts) {
  if (parts == 0 || nodes.size() - at < 2 * static_cast<size_t>(parts))
    return false;
  std::optional<uint64_t> below;
  for (uint32_t part = 0; part < parts; ++part) {
    const TermNode &times = nodes[at + 2 * part];
    const TermNode &level = nodes[at + 2 * part + 1];
    if (times.kind != TermKind::Multiple || times.value == 0 || level.kind != TermKind::Level ||
        (below && level.value <= *below))
      return false;
    below = level.value;
  }
  return parts > 1 || nodes[at].value > 1;
}

} // namespace

// Iterative: a term as deep as a long list is walked with a count of the
// nodes still owed, never with a recursion on its depth.
size_t extentOf(ArrayRef<TermNode> nodes, size_t at) {
  uint64_t owed = 1;
  size_t end = at;
  while (owed > 0) {
    const TermNode &node = nodes[end++];
    --owed;
    owed += owedBy(node);
  }
  return end - at;
}

// The nodes a successor or a sum owns are read whole where it is met, so
// only a constructor's arguments are owed past it, each a whole term.
std::optional<size_t> countTerms(ArrayRef<TermNode> nodes) {
  size_t terms = 0;
  uint64_t owed = 0;
  for (size_t at = 0; at < nodes.size();) {
    if (owed == 0)
      ++terms;
    else
      --owed;
    const TermNode &node = nodes[at++];
    switch (node.kind) {
    case TermKind::Natural:
    case TermKind::Level:
    case TermKind::Literal:
    case TermKind::Opaque:
      break;
    case TermKind::Constructor:
      owed += node.arity;
      break;
    case TermKind::Successor:
      if (node.value == 0 || at == nodes.size() || nodes[at].kind != TermKind::Level)
        return std::nullopt;
      ++at;
      break;
    case TermKind::Sum:
      if (!normalParts(nodes, at, node.arity))
        return std::nullopt;
      at += 2 * static_cast<size_t>(node.arity);
      break;
    // A part stands only inside its sum, which read it.
    case TermKind::Multiple:
      return std::nullopt;
    }
  }
  if (owed != 0)
    return std::nullopt;
  return terms;
}

Term::Term(ArrayRef<TermNode> nodes) : nodes_(nodes.take_front(extentOf(nodes, 0))) {}

Term Term::child(unsigned index) const {
  size_t at = 1;
  for (unsigned skipped = 0; skipped < index; ++skipped)
    at += extentOf(nodes_, at);
  return Term(nodes_.drop_front(at));
}

bool Term::isClosed() const {
  return llvm::none_of(nodes_, [](const TermNode &node) {
    return node.kind == TermKind::Level || node.kind == TermKind::Opaque;
  });
}

uint32_t freeLevelsOf(ArrayRef<TermNode> nodes) {
  uint32_t depth = 0;
  for (const TermNode &node : nodes)
    if (node.kind == TermKind::Level)
      depth = std::max(depth, static_cast<uint32_t>(node.value) + 1);
  return depth;
}

uint32_t Term::freeLevels() const { return freeLevelsOf(nodes_); }

SmallVector<Term> termsOf(ArrayRef<TermNode> nodes, size_t count) {
  SmallVector<Term> out;
  size_t at = 0;
  for (size_t index = 0; index < count; ++index) {
    out.push_back(Term(nodes.drop_front(at)));
    at += out.back().nodes().size();
  }
  return out;
}

// A Constructor's arity counts the terms after its head; every other kind's
// is 0.
SmallVector<Term> argumentsOf(Term term) {
  return termsOf(term.nodes().drop_front(), term.head().arity);
}

//===----------------------------------------------------------------------===//
// Normal forms
//===----------------------------------------------------------------------===//

namespace {

// A count that stays a word: a sum or a product past it is no natural the
// storage holds, so its term is opaque.
std::optional<uint64_t> addCounts(uint64_t a, uint64_t b) {
  if (a > std::numeric_limits<uint64_t>::max() - b)
    return std::nullopt;
  return a + b;
}

std::optional<uint64_t> timesCount(uint64_t a, uint64_t b) {
  if (b != 0 && a > std::numeric_limits<uint64_t>::max() / b)
    return std::nullopt;
  return a * b;
}

} // namespace

void NatSum::add(Term term, uint64_t times, uint32_t shift) {
  if (!linear)
    return;
  std::optional<uint64_t> count = forEachPart(term, [&](uint32_t level, uint64_t occurs) {
    std::optional<uint64_t> both = timesCount(occurs, times);
    if (!both)
      return forget();
    addLevel(level + shift, *both);
  });
  if (!count)
    return forget();
  addCount(*count, times);
}

// The parts stay ascending, each level once: a level met again adds to how
// often it occurs.
void NatSum::addLevel(uint32_t level, uint64_t times) {
  if (!linear || times == 0)
    return;
  auto &parts = linear->parts;
  auto *at = llvm::lower_bound(parts, level,
                               [](const auto &part, uint32_t key) { return part.first < key; });
  if (at != parts.end() && at->first == level) {
    std::optional<uint64_t> occurs = addCounts(at->second, times);
    if (!occurs)
      return forget();
    at->second = *occurs;
    return;
  }
  parts.insert(at, {level, times});
}

void NatSum::addCount(uint64_t count, uint64_t times) {
  if (!linear)
    return;
  std::optional<uint64_t> product = timesCount(count, times);
  std::optional<uint64_t> sum = product ? addCounts(linear->count, *product) : std::nullopt;
  if (!sum)
    return forget();
  linear->count = *sum;
}

void TermWriter::natural(uint64_t value) {
  out.push_back({TermKind::Natural, 0, 0, value, Attribute()});
}

void TermWriter::level(uint32_t level, uint64_t plus) {
  if (plus > 0)
    out.push_back({TermKind::Successor, 0, 0, plus, Attribute()});
  out.push_back({TermKind::Level, 0, 0, level, Attribute()});
}

void TermWriter::literal(Attribute constant) {
  out.push_back({TermKind::Literal, 0, 0, 0, constant});
}

void TermWriter::opaque() { out.push_back({TermKind::Opaque, 0, 0, 0, Attribute()}); }

void TermWriter::constructor(Attribute group, uint32_t member, uint64_t tag, uint32_t arity) {
  out.push_back({TermKind::Constructor, member, arity, tag, group});
}

void TermWriter::sum(const NatSum &sum) {
  if (!sum.linear)
    return opaque();
  const auto &[parts, count] = *sum.linear;
  if (parts.empty())
    return natural(count);
  if (parts.size() == 1 && parts.front().second == 1)
    return level(parts.front().first, count);
  out.push_back({TermKind::Sum, 0, static_cast<uint32_t>(parts.size()), count, Attribute()});
  for (auto [at, times] : parts) {
    out.push_back({TermKind::Multiple, 0, 0, times, Attribute()});
    out.push_back({TermKind::Level, 0, 0, at, Attribute()});
  }
}

// A literal or a constructor is copied node by node, its levels shifted: a
// constructor's arguments are whole terms in normal form already. Every
// other term, and either of those plus a positive count, is added up, which
// writes its normal form: only a term of a natural's sort has a successor,
// so a constructor or a literal plus one is no term of the language, and
// opaque.
void TermWriter::copy(Term term, uint64_t plus, uint32_t shift) {
  if (plus == 0 && (term.kind() == TermKind::Literal || term.kind() == TermKind::Constructor)) {
    for (TermNode node : term.nodes()) {
      if (node.kind == TermKind::Level)
        node.value += shift;
      out.push_back(node);
    }
    return;
  }
  NatSum total;
  total.add(term, 1, shift);
  total.addCount(plus);
  sum(total);
}

} // namespace idr::families
