// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A family's declaration as #idr.family holds it: a group of members, each
// Idris's data, a closure sum or a memo sum, with its index sorts and its
// constructors, each constructor with the index variables it binds, the
// equation its result satisfies and its fields. The group is an attribute
// whose storage is its content, so equal declarations are one attribute,
// shared by MLIR's uniquing, with no table and no name looked up; a member
// of the group names another by position (`!idr.self`), which keeps the
// attribute acyclic, so the uniquer, the printer and bytecode hold it as
// any attribute. Labels are part of the content: two declarations equal but
// for their labels are two families.
//
// What a reader needs of a member, whatever its kind, is its constructors:
// a data member's are declared, a closure sum's are its labels (the fields
// its captures), and a memo sum's are its labels and then its two states,
// `running` (no field) and `forced` (the forced value), which every
// application of it has. So one view, CtorView, gives a constructor of any
// member, and a reader that needs what one kind has asks for that kind.
#ifndef IDR_IR_FAMILIES_DECLARATION_H
#define IDR_IR_FAMILIES_DECLARATION_H

#include "idr/IR/Families/Terms.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/Location.h"
#include "mlir/IR/Types.h"

#include <optional>
#include <variant>

namespace idr {

// A constructor's tag: its position among its member's constructors, the
// number a cell's header and a match's case hold.
enum class Tag : uint32_t {};

inline llvm::raw_ostream &operator<<(llvm::raw_ostream &os, Tag tag) {
  return os << static_cast<uint32_t>(tag);
}

namespace families {

// A data constructor, or a frame.
struct CtorDecl {
  mlir::StringAttr label;
  llvm::ArrayRef<Sort> binders;
  // One term per index of its member, over its binders.
  llvm::ArrayRef<TermNode> equation;
  // Over its binders; each a field type, `!idr.graded<once, T>` for a field
  // used once and the bare T for one used many times.
  llvm::ArrayRef<mlir::Type> fields;

  bool operator==(const CtorDecl &) const = default;
};

// A label of a closure or memo sum: the function it runs, and its fields,
// the function's captures.
struct LabelDecl {
  mlir::StringAttr label;
  mlir::FlatSymbolRefAttr fn;
  llvm::ArrayRef<Sort> binders;
  llvm::ArrayRef<TermNode> equation;
  llvm::ArrayRef<mlir::Type> fields;

  bool operator==(const LabelDecl &) const = default;
};

struct MemoLabelDecl {
  Mode mode;
  LabelDecl label;

  bool operator==(const MemoLabelDecl &) const = default;
};

struct DataMember {
  mlir::StringAttr label;
  mlir::LocationAttr loc;
  Promise promise;
  llvm::ArrayRef<Sort> indices;
  llvm::ArrayRef<CtorDecl> ctors;

  bool operator==(const DataMember &) const = default;
};

struct ClosuresMember {
  mlir::StringAttr label;
  llvm::ArrayRef<Sort> indices;
  llvm::ArrayRef<LabelDecl> labels;

  bool operator==(const ClosuresMember &) const = default;
};

struct MemoMember {
  mlir::StringAttr label;
  llvm::ArrayRef<Sort> indices;
  llvm::ArrayRef<MemoLabelDecl> labels;
  // Over the member's indices, as levels 0 to n-1.
  mlir::Type forced;

  bool operator==(const MemoMember &) const = default;
};

// A frame stack: the continuations a recursion on a call cycle pushes, one
// stack per awaited result. Its one index is a natural (each constructor's
// equation `nat j`), its constructors ordinary ones whose fields hold what
// a frame keeps (any field type, lifetimes, packages, reuse tokens and
// destinations among them), each at the whole grade the value has, given
// back so at the pop; a constructor's field of its own member is the
// frame below, and one with none is a base frame, which takes a fresh
// chunk. A frame is pushed once and popped by one resume, so the stack is
// linear by its type and never counted.
struct FramesMember {
  mlir::StringAttr label;
  llvm::ArrayRef<CtorDecl> ctors;

  bool operator==(const FramesMember &) const = default;
};

// A member of a family as a claim names it: its group, null for the group
// that names it, and its position there.
struct MemberRef {
  mlir::Attribute group;
  uint32_t member;

  bool operator==(const MemberRef &) const = default;
};

// A member: its alternative is its kind, in MemberKind's order.
using Member = std::variant<DataMember, ClosuresMember, MemoMember, FramesMember>;

llvm::hash_code hash_value(const Member &member);

// The labels of a memo sum's two states, which their positions identify;
// a reader finds a state by its position, never by its label.
inline constexpr llvm::StringLiteral memoRunning = "running";
inline constexpr llvm::StringLiteral memoForced = "forced";

// Any member's constructor `tag`, whatever its kind: its label, binders,
// equation and fields. A memo sum's states are views of what its storage
// holds for them: `running` binds the member's indices and has no field,
// `forced` binds them and holds the forced value.
struct CtorView {
  llvm::StringRef label;
  llvm::ArrayRef<Sort> binders;
  llvm::ArrayRef<TermNode> equation;
  llvm::ArrayRef<mlir::Type> fields;
};

// A memo sum: its labels first, by tag, then `running`, then `forced`.
struct MemoView {
  llvm::ArrayRef<MemoLabelDecl> labels_;
  llvm::ArrayRef<MemoLabelDecl> labels() const { return labels_; }
  Tag running() const { return Tag{static_cast<uint32_t>(labels_.size())}; }
  Tag forced() const { return Tag{static_cast<uint32_t>(labels_.size()) + 1}; }
};

// A closure sum: its labels, by tag.
struct ClosuresView {
  llvm::ArrayRef<LabelDecl> labels_;
  llvm::ArrayRef<LabelDecl> labels() const { return labels_; }
};

// What a member of numeral shape keeps for its bound: the index position
// its successor's field descends at, the argument of that position's term
// the field's index is (none for a natural's successor), and how many
// layers its zero needs. A numeral that descends at no index is a natural
// at every application, which is the problem's own case (Nat-like types
// with no bound), not a missing fact.
struct Descent {
  uint32_t position;
  std::optional<uint32_t> argument;
  uint64_t zeroDepth;
  // The successor, whose own layer the depth counts.
  Tag successor;
};

// A member's derived shape: base's list (a field-less constructor and one
// of an element and itself) is read by the string ops; a numeral (a
// field-less constructor and one whose only field is itself) is a number.
// Read off the declaration, never named.
enum class Shape : uint8_t { Plain, List, Numeral };

struct ListShape {
  Tag nil;
  Tag cons;
  // The element's position among cons's fields; the tail is the other.
  unsigned element;
};

// Whether a group holds itself: a field of one of its members names one of
// them. A group is a strongly connected component, so when it holds itself
// every member lies on the cycle.
enum class Containment : uint8_t { Acyclic, HoldsItself };

} // namespace families
} // namespace idr

#endif // IDR_IR_FAMILIES_DECLARATION_H
