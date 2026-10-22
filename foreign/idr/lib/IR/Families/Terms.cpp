// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Index terms over their nodes: their extent, their levels, their normal
// form, and how a term is written. A constructor term is written with its
// family and its label, read into its tag here, at the boundary. A sort is
// written beside the scopes that bind it (Scopes.cpp).

#include "idr/IR/Families/Terms.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/DialectImplementation.h"
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

SmallVector<Term> Term::arguments() const {
  SmallVector<Term> out;
  size_t at = 1;
  for (uint32_t index = 0; index < head().arity; ++index) {
    out.push_back(Term(nodes_.drop_front(at)));
    at += out.back().nodes().size();
  }
  return out;
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

//===----------------------------------------------------------------------===//
// Terms in text
//===----------------------------------------------------------------------===//

// A constructor names its family whatever its position: `#G @Cons(v0, v1)`,
// `self at 1 @Here`. So a term reads with no sort at hand, and a term of a
// group still being read keeps its label until the group's labels are all
// known.
void printTerm(AsmPrinter &printer, Term term, Attribute ownGroup) {
  const TermNode &head = term.head();
  switch (head.kind) {
  case TermKind::Natural:
    printer << head.value;
    return;
  case TermKind::Level:
    printer << 'v' << head.value;
    return;
  case TermKind::Successor:
    printer << 'v' << term.child(0).head().value << " + " << head.value;
    return;
  case TermKind::Literal:
    printer << "lit ";
    if (auto type = dyn_cast<TypeAttr>(head.payload)) {
      printer << "type ";
      printer.printType(type.getValue());
      return;
    }
    printer.printAttribute(head.payload);
    return;
  case TermKind::Opaque:
    printer << '_';
    return;
  case TermKind::Constructor: {
    if (head.payload)
      printer.printAttribute(head.payload);
    else
      printer << "self";
    if (head.member != 0)
      printer << " at " << head.member;
    printer << ' ';
    auto group = cast<FamilyAttr>(head.payload ? head.payload : ownGroup);
    printer.printSymbolName(group.ctor(head.member, Tag{static_cast<uint32_t>(head.value)}).label);
    if (head.arity == 0)
      return;
    printer << '(';
    llvm::interleaveComma(term.arguments(), printer,
                          [&](Term argument) { printTerm(printer, argument, ownGroup); });
    printer << ')';
    return;
  }
  }
}

void printTerms(AsmPrinter &printer, ArrayRef<TermNode> nodes, size_t count, Attribute ownGroup) {
  llvm::interleaveComma(termsOf(nodes, count), printer,
                        [&](Term term) { printTerm(printer, term, ownGroup); });
}

ParseResult resolveLabel(AsmParser &parser, TermNode &node, FamilyAttr group, StringRef label,
                         SMLoc at) {
  if (node.member >= group.getMembers().size())
    return parser.emitError(at, "expects a member of the family, got member ") << node.member;
  std::optional<Tag> tag = group.tagOf(node.member, label);
  if (!tag)
    return parser.emitError(at, "expects a constructor of the family, got @") << label;
  CtorView ctor = group.ctor(node.member, *tag);
  if (node.arity != ctor.binders.size() + ctor.fields.size())
    return parser.emitError(at, "expects @")
           << label << " applied to its " << ctor.binders.size() + ctor.fields.size()
           << " binders and fields";
  node.value = static_cast<uint32_t>(*tag);
  return success();
}

ParseResult parseTerm(AsmParser &parser, SmallVectorImpl<TermNode> &out,
                      SmallVectorImpl<PendingLabel> *pending) {
  TermWriter write(out);
  SMLoc at = parser.getCurrentLocation();
  if (succeeded(parser.parseOptionalKeyword("_"))) {
    write.opaque();
    return success();
  }
  if (succeeded(parser.parseOptionalKeyword("lit"))) {
    if (succeeded(parser.parseOptionalKeyword("type"))) {
      Type type;
      if (parser.parseType(type))
        return failure();
      write.literal(TypeAttr::get(type));
      return success();
    }
    Attribute constant;
    if (parser.parseAttribute(constant))
      return failure();
    write.literal(constant);
    return success();
  }
  uint64_t number;
  OptionalParseResult natural = parser.parseOptionalInteger(number);
  if (natural.has_value()) {
    if (failed(*natural))
      return failure();
    write.natural(number);
    return success();
  }
  // A constructor: its family, then its label in it.
  Attribute group;
  bool own = succeeded(parser.parseOptionalKeyword("self"));
  if (!own) {
    OptionalParseResult attr = parser.parseOptionalAttribute(group);
    if (!attr.has_value()) {
      // A level is `v<k>`, a bare keyword, then perhaps `+ n`.
      StringRef keyword;
      uint32_t level;
      if (parser.parseKeyword(&keyword) || !keyword.consume_front("v") ||
          keyword.getAsInteger(10, level))
        return parser.emitError(at, "expects an index term");
      uint64_t plus = 0;
      if (succeeded(parser.parseOptionalPlus()) && parser.parseInteger(plus))
        return failure();
      write.level(level, plus);
      return success();
    }
    if (failed(*attr))
      return failure();
    if (!isa<FamilyAttr>(group))
      return parser.emitError(at, "expects a family, got ") << group;
  }
  uint32_t member = 0;
  if (succeeded(parser.parseOptionalKeyword("at")) && parser.parseInteger(member))
    return failure();
  std::string label;
  SMLoc labelAt = parser.getCurrentLocation();
  if (parser.parseSymbolName(label))
    return failure();
  size_t node = out.size();
  write.constructor(group, member, 0, 0);
  uint32_t arity = 0;
  if (succeeded(parser.parseOptionalLParen())) {
    do {
      if (parseTerm(parser, out, pending))
        return failure();
      ++arity;
    } while (succeeded(parser.parseOptionalComma()));
    if (parser.parseRParen())
      return failure();
  }
  out[node].arity = arity;
  if (own) {
    if (!pending)
      return parser.emitError(at, "expects no constructor of a group being declared here");
    pending->push_back({&out, node, label, labelAt});
    return success();
  }
  return resolveLabel(parser, out[node], cast<FamilyAttr>(group), label, labelAt);
}

ParseResult parseTerms(AsmParser &parser, size_t count, SmallVectorImpl<TermNode> &out,
                       SmallVectorImpl<PendingLabel> *pending) {
  for (size_t index = 0; index < count; ++index) {
    if (index > 0 && parser.parseComma())
      return failure();
    if (parseTerm(parser, out, pending))
      return failure();
  }
  return success();
}

} // namespace idr::families
