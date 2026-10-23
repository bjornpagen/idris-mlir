// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The index language of a family, as the storage of a type holds it: a
// term is a preorder array of nodes inside whatever holds it (a data type's
// indices, a constructor's equation), never an attribute per subterm, so a
// type's facts are computed over plain arrays when the type is made and no
// storage is created while they are. The kinds of node and of sort are the
// specification's (IdrisMLIR.Spec.Families.Terms), printed into the
// generated header.
//
// A term is in normal form by construction: a natural is a number, a
// successor applies only to a level, two successors never nest, a sum of
// naturals is each level once with how often it occurs, ascending, then a
// count (two occurrences at least: one level once is a level or its
// successor), and anything the language has no term for is opaque. A
// natural past a machine word is opaque too: a count is a word in the
// storage, so making a type does no arithmetic on attributes; such a term
// refines nothing, which is sound, and no program is refused for it.
#ifndef IDR_IR_FAMILIES_TERMS_H
#define IDR_IR_FAMILIES_TERMS_H

#include "mlir/IR/AttrTypeSubElements.h"
#include "mlir/IR/Attributes.h"
#include "mlir/IR/OpImplementation.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/Hashing.h"
#include "llvm/ADT/SmallVector.h"

#include <concepts>
#include <cstdint>
#include <optional>
#include <string>
#include <utility>

// TermKind, SortKind, Promise, Mode, MemberKind, Layout, Class and the
// shape budget, from the specification.
#include "idr/IR/Generated/Families.h.inc"

namespace idr::families {

// One node of a term. A Constructor node is followed by its arguments (the
// constructor's binders, then its fields), a Successor node by its level, a
// Sum node by its parts, each a Multiple node followed by its level, so a
// term's extent is read off its nodes with no declaration at hand.
struct TermNode {
  TermKind kind;
  // Constructor: its member in its group.
  uint32_t member = 0;
  // Constructor: how many terms follow it as its arguments. Sum: how many
  // parts follow it.
  uint32_t arity = 0;
  // Natural: the number. Level: the level. Successor: the count added, at
  // least one. Sum: the count added. Multiple: how often its level occurs,
  // at least once. Constructor: the tag.
  uint64_t value = 0;
  // Literal: the constant (a typed attribute, or a TypeAttr for a type).
  // Constructor: its group, null for the group the term is declared in.
  mlir::Attribute payload;

  bool operator==(const TermNode &) const = default;
};

llvm::hash_code hash_value(const TermNode &node);

// The sort of an index position or a constructor's binder.
struct Sort {
  SortKind kind;
  // FamilySort: the member in its group.
  uint32_t member = 0;
  // ScalarSort: the scalar's TypeAttr. FamilySort: the group, null for the
  // group the sort is declared in.
  mlir::Attribute payload;

  bool operator==(const Sort &) const = default;
};

llvm::hash_code hash_value(const Sort &sort);

} // namespace idr::families

// A node's and a sort's one attribute (a literal, a constructor's group, a
// scalar's type, a family), walked and replaced as MLIR walks any
// parameter, so every storage that keys on them derives its sub-elements
// from its key.
template <>
struct mlir::AttrTypeSubElementHandler<idr::families::TermNode> {
  static void walk(const idr::families::TermNode &node, AttrTypeImmediateSubElementWalker &walker) {
    walker.walk(node.payload);
  }
  static idr::families::TermNode replace(const idr::families::TermNode &node,
                                         AttrSubElementReplacements &attrs,
                                         TypeSubElementReplacements &) {
    idr::families::TermNode out = node;
    if (node.payload)
      out.payload = attrs.take_front(1)[0];
    return out;
  }
};

template <>
struct mlir::AttrTypeSubElementHandler<idr::families::Sort> {
  static void walk(const idr::families::Sort &sort, AttrTypeImmediateSubElementWalker &walker) {
    walker.walk(sort.payload);
  }
  static idr::families::Sort replace(const idr::families::Sort &sort,
                                     AttrSubElementReplacements &attrs,
                                     TypeSubElementReplacements &) {
    idr::families::Sort out = sort;
    if (sort.payload)
      out.payload = attrs.take_front(1)[0];
    return out;
  }
};

namespace idr::families {

// A term: a view of the nodes of one term, its head first.
class Term {
public:
  // The term whose head is `nodes.front()`, which `nodes` holds whole.
  explicit Term(llvm::ArrayRef<TermNode> nodes);

  const TermNode &head() const { return nodes_.front(); }
  TermKind kind() const { return head().kind; }
  llvm::ArrayRef<TermNode> nodes() const { return nodes_; }

  // A Successor's level; a Constructor's argument `index`. All of a
  // Constructor's arguments are argumentsOf's: a vector of terms cannot be
  // named here, where the term is not yet a complete type.
  Term child(unsigned index) const;

  // Whether it names no level and holds nothing opaque: a value the class
  // rule may unfold.
  bool isClosed() const;
  // One more than its largest level, 0 when it names none: the depth a
  // scope needs for the term to be in it.
  uint32_t freeLevels() const;

  bool operator==(const Term &other) const { return nodes_ == other.nodes_; }

private:
  llvm::ArrayRef<TermNode> nodes_;
};

// The number of nodes of the term that starts at `nodes[at]`, a term whole
// in `nodes`.
size_t extentOf(llvm::ArrayRef<TermNode> nodes, size_t at);

// How many whole terms in normal form `nodes` holds one after the other,
// or none where the last runs past its end or a node breaks the normal
// form (a successor of no level or of nothing, a sum whose parts are not
// its levels ascending each at least once, or one level once; a part of a
// sum outside one): what a reader of nodes no builder wrote (a bytecode
// read, a verifier) asks before any walk that trusts extents, so every
// term past it is one TermWriter could have written.
std::optional<size_t> countTerms(llvm::ArrayRef<TermNode> nodes);

// The parts of a natural term, each level with how often it occurs,
// ascending, given to `each`, and its count: a natural's value and no
// part, a level once, a successor's level once and its count, a sum's own.
// None for a term of no natural's form (a literal, a constructor, an opaque
// term), whose parts nothing reads.
template <class Each>
  requires std::invocable<Each &, uint32_t, uint64_t>
std::optional<uint64_t> forEachPart(Term term, Each &&each);

// The `count` terms `nodes` holds one after the other, as a type's indices
// and an equation are held.
llvm::SmallVector<Term> termsOf(llvm::ArrayRef<TermNode> nodes, size_t count);

// A Constructor's arguments, the terms that follow its head; none for any
// other term.
llvm::SmallVector<Term> argumentsOf(Term term);

// One more than the largest level of any of `nodes`.
uint32_t freeLevelsOf(llvm::ArrayRef<TermNode> nodes);

// A natural being added up, as a substitution or a parse meets one: each
// level with how often it occurs, ascending, and a count; or nothing the
// language says, once anything added is no natural (a literal, a
// constructor, an opaque term) or a count passes a word, which is opaque.
// TermWriter::sum writes its normal form, so `v + w` and `w + v`, and a
// sum whose levels all became naturals, are written as one term each.
class NatSum {
public:
  // `term`, taken `times` times, its levels shifted by `shift`.
  void add(Term term, uint64_t times = 1, uint32_t shift = 0);
  // Level `level`, `times` times.
  void addLevel(uint32_t level, uint64_t times = 1);
  // `count`, `times` times.
  void addCount(uint64_t count, uint64_t times = 1);
  // Something the language has no natural for.
  void forget() { linear.reset(); }

private:
  friend class TermWriter;
  struct Linear {
    llvm::SmallVector<std::pair<uint32_t, uint64_t>, 4> parts;
    uint64_t count = 0;
  };
  std::optional<Linear> linear = Linear{};
};

// Writes normal forms, so no caller makes a successor of a successor or of
// a natural, a natural out of successors, or a sum of one level once or of
// a level twice.
class TermWriter {
public:
  explicit TermWriter(llvm::SmallVectorImpl<TermNode> &out) : out(out) {}

  void natural(uint64_t value);
  // Level `level` plus `plus`.
  void level(uint32_t level, uint64_t plus = 0);
  void literal(mlir::Attribute constant);
  void opaque();
  // The head of constructor `tag` of `member` of `group`; its `arity`
  // arguments are written after it.
  void constructor(mlir::Attribute group, uint32_t member, uint64_t tag, uint32_t arity);
  // What `sum` added up, in normal form: opaque, a natural, a level plus
  // its count, or a sum.
  void sum(const NatSum &sum);
  // `term` plus `plus`, its levels shifted by `shift`: plus 0 copies it.
  void copy(Term term, uint64_t plus = 0, uint32_t shift = 0);

private:
  llvm::SmallVectorImpl<TermNode> &out;
};

template <class Each>
  requires std::invocable<Each &, uint32_t, uint64_t>
std::optional<uint64_t> forEachPart(Term term, Each &&each) {
  llvm::ArrayRef<TermNode> nodes = term.nodes();
  const TermNode &head = nodes.front();
  switch (head.kind) {
  case TermKind::Natural:
    return head.value;
  case TermKind::Level:
    each(static_cast<uint32_t>(head.value), uint64_t{1});
    return uint64_t{0};
  case TermKind::Successor:
    each(static_cast<uint32_t>(nodes[1].value), uint64_t{1});
    return head.value;
  case TermKind::Sum:
    // Each part is its multiple, then its level.
    for (uint32_t part = 0; part < head.arity; ++part)
      each(static_cast<uint32_t>(nodes[2 + 2 * part].value), nodes[1 + 2 * part].value);
    return head.value;
  case TermKind::Multiple:
  case TermKind::Literal:
  case TermKind::Constructor:
  case TermKind::Opaque:
    break;
  }
  return std::nullopt;
}

// A constructor of the group a declaration is still reading, which has no
// attribute yet, read by its label: its node, written with no tag, is
// resolved once the whole group is read (FamilyAttr::parse), since a label
// may name a member read after it. Only an equation, which the group's
// parser reads itself, holds one; a field's type is read by the type
// parser, which has no group to resolve against, so a field indexed by a
// constructor of its own group has no text (bytecode carries it).
struct PendingLabel {
  llvm::SmallVectorImpl<TermNode> *nodes;
  size_t node;
  std::string label;
  llvm::SMLoc at;
};

// How a term is written in the IR: `3`, `v1`, `v1 + 2`, a sum
// `v0 + v1 * 2 + 3` (each level once, ascending, how often it occurs after
// `*` where that is more than once, then the count where there is one; read
// in any order and added up, so it is made in normal form), `lit 7 : i64`,
// `lit type i64`, `_`, and a constructor by its family and its label in
// it, `#List @Cons(v0, #List @Nil)`, `self at 1 @Here` in its own group, so
// a term reads with no sort at hand. A label is read into its tag here, at
// the boundary, and nothing after reads one. `ownGroup` is the group a null
// payload names, when the printer has it.
void printTerm(mlir::AsmPrinter &printer, Term term, mlir::Attribute ownGroup);
void printTerms(mlir::AsmPrinter &printer, llvm::ArrayRef<TermNode> nodes, size_t count,
                mlir::Attribute ownGroup);
// Reads one term into `out`. A constructor of another group is resolved
// in it; one of the group being read goes to `pending`, and is an error
// where there is none.
mlir::ParseResult parseTerm(mlir::AsmParser &parser, llvm::SmallVectorImpl<TermNode> &out,
                            llvm::SmallVectorImpl<PendingLabel> *pending);
// `count` terms separated by commas.
mlir::ParseResult parseTerms(mlir::AsmParser &parser, size_t count,
                             llvm::SmallVectorImpl<TermNode> &out,
                             llvm::SmallVectorImpl<PendingLabel> *pending);

// How a sort is written: `nat`, `type`, `opaque`, a scalar type, or a
// family member, `#G` or `#G at 1`, `self` or `self at 1` in its own group.
void printSort(mlir::AsmPrinter &printer, const Sort &sort);
mlir::ParseResult parseSort(mlir::AsmParser &parser, Sort &sort);

} // namespace idr::families

#endif // IDR_IR_FAMILIES_TERMS_H
