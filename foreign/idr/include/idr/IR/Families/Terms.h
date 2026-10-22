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
// successor applies only to a level, two successors never nest, and
// anything the language has no term for is opaque. A natural past a
// machine word is opaque too: a count is a word in the storage, so making a
// type does no arithmetic on attributes; such a term refines nothing, which
// is sound, and no program is refused for it.
#ifndef IDR_IR_FAMILIES_TERMS_H
#define IDR_IR_FAMILIES_TERMS_H

#include "mlir/IR/AttrTypeSubElements.h"
#include "mlir/IR/Attributes.h"
#include "mlir/IR/OpImplementation.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/Hashing.h"
#include "llvm/ADT/SmallVector.h"

#include <cstdint>
#include <optional>
#include <string>

// TermKind, SortKind, Promise, Mode, MemberKind, Layout, Class and the
// shape budget, from the specification.
#include "idr/IR/Generated/Families.h.inc"

namespace idr::families {

// One node of a term. A Constructor node is followed by its arguments (the
// constructor's binders, then its fields), a Successor node by its level,
// so a term's extent is read off its nodes with no declaration at hand.
struct TermNode {
  TermKind kind;
  // Constructor: its member in its group.
  uint32_t member = 0;
  // Constructor: how many terms follow it as its arguments.
  uint32_t arity = 0;
  // Natural: the number. Level: the level. Successor: the count added, at
  // least one. Constructor: the tag.
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

// How many whole terms `nodes` holds one after the other, or none where the
// last runs past its end: what a reader of nodes no builder wrote (a parse,
// a bytecode read, a verifier) asks before any walk that trusts extents.
std::optional<size_t> countTerms(llvm::ArrayRef<TermNode> nodes);

// The `count` terms `nodes` holds one after the other, as a type's indices
// and an equation are held.
llvm::SmallVector<Term> termsOf(llvm::ArrayRef<TermNode> nodes, size_t count);

// A Constructor's arguments, the terms that follow its head; none for any
// other term.
llvm::SmallVector<Term> argumentsOf(Term term);

// One more than the largest level of any of `nodes`.
uint32_t freeLevelsOf(llvm::ArrayRef<TermNode> nodes);

// Writes normal forms, so no caller makes a successor of a successor or of
// a natural, or a natural out of successors.
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
  // `term` plus `plus`, its levels shifted by `shift`: plus 0 copies it.
  void copy(Term term, uint64_t plus = 0, uint32_t shift = 0);

private:
  llvm::SmallVectorImpl<TermNode> &out;
};

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

// How a term is written in the IR: `3`, `v1`, `v1 + 2`, `lit 7 : i64`,
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
