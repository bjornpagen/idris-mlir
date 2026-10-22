// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Index terms over their nodes: their extent, their levels and their
// normal form. How a term is written is TermSyntax.cpp's.

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

// Iterative: a term as deep as a long list is walked with a count of the
// nodes still owed, never with a recursion on its depth.
size_t extentOf(ArrayRef<TermNode> nodes, size_t at) {
  size_t owed = 1;
  size_t end = at;
  while (owed > 0) {
    const TermNode &node = nodes[end++];
    --owed;
    if (node.kind == TermKind::Successor)
      owed += 1;
    else if (node.kind == TermKind::Constructor)
      owed += node.arity;
  }
  return end - at;
}

std::optional<size_t> countTerms(ArrayRef<TermNode> nodes) {
  size_t terms = 0;
  uint64_t owed = 0;
  for (const TermNode &node : nodes) {
    if (owed == 0)
      ++terms;
    else
      --owed;
    if (node.kind == TermKind::Successor)
      owed += 1;
    else if (node.kind == TermKind::Constructor)
      owed += node.arity;
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

// A count that stays a word: a sum past it is no natural the storage
// holds, so its term is opaque.
std::optional<uint64_t> addCounts(uint64_t a, uint64_t b) {
  if (a > std::numeric_limits<uint64_t>::max() - b)
    return std::nullopt;
  return a + b;
}

} // namespace

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

// Plus a positive count, only a term of a natural's sort has a successor:
// a constructor or a literal plus one is no term of the language, so it is
// opaque.
void TermWriter::copy(Term term, uint64_t plus, uint32_t shift) {
  const TermNode &head = term.head();
  switch (head.kind) {
  case TermKind::Natural:
    if (std::optional<uint64_t> sum = addCounts(head.value, plus))
      return natural(*sum);
    return opaque();
  case TermKind::Level:
    return level(static_cast<uint32_t>(head.value) + shift, plus);
  case TermKind::Successor: {
    std::optional<uint64_t> sum = addCounts(head.value, plus);
    if (!sum)
      return opaque();
    return level(static_cast<uint32_t>(term.child(0).head().value) + shift, *sum);
  }
  case TermKind::Opaque:
    return opaque();
  case TermKind::Literal:
  case TermKind::Constructor:
    if (plus > 0)
      return opaque();
    // Copied node by node, levels shifted: a constructor's arguments are
    // whole terms in normal form already.
    for (TermNode node : term.nodes()) {
      if (node.kind == TermKind::Level)
        node.value += shift;
      out.push_back(node);
    }
    return;
  }
}

} // namespace idr::families
