// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The one unifier of index terms, which every reader of a refinement calls:
// a type's possible constructors when it is made, a case's refinement in
// the scope walk, an assumed equation, a binder a constructor's equation
// determines. It restates Idris's own rule for an impossible case (a clash
// between distinct constructors, distinct literals or naturals, or a level
// that occurs under a constructor or a successor in its own binding), so it
// never finds a clash Idris's elaborator would not, and an opaque term
// clashes with nothing and binds nothing, but where a match asks for one
// type as an instance of another.
//
// It runs over plain node arrays and words, creating no attribute, so a
// type's storage calls it while it is made. Two scopes of levels meet in it
// (an application's and a constructor's binders), each a Side; a binding is
// a view of a term of either side, plus a count.
#ifndef IDR_IR_FAMILIES_UNIFY_H
#define IDR_IR_FAMILIES_UNIFY_H

#include "idr/IR/Families/Terms.h"

#include "llvm/ADT/SmallVector.h"

#include <optional>

namespace idr::families {

// Which scope a term's levels are of.
enum class Side : uint8_t { Application, Constructor };

// A term of one side, plus a count: what a level is bound to, `nat (n - k)`
// where a natural met a successor having no node of its own (no nodes, the
// count the natural).
struct Bound {
  llvm::ArrayRef<TermNode> nodes;
  Side side;
  uint64_t plus;
};

// Whether a level of a side is free to bind (an unknown) or stands for
// itself (rigid): a type's possible constructors take every level as an
// unknown; a constructor's binders read off a type take the type's levels
// as rigid.
enum class Freedom : uint8_t { Unknown, Rigid };

// What an opaque term of the application side meets: anything, since it
// says nothing, so a refinement, a type's possible constructors and a
// binder an equation solves learn nothing from it; or only what leaves it
// open, an opaque term or a free level of the other side, where a type is
// matched as an instance of a pattern: an index the type does not name is
// no index the pattern names, so `#Vect[3]` is an instance of
// `#Vect[_]` and `#Vect[_]` is none of `#Vect[3]`.
enum class Opacity : uint8_t { MeetsAnything, StaysOpen };

// Whether an instance names a constructor binder no binding replaced.
enum class Instance : uint8_t { Determined, Undetermined };

// A substitution of levels of both sides, by level: each side's levels
// below its width.
class Subst {
public:
  // `own` is the group a null group in a term stands for: the declaration
  // the constructor's equation is in.
  Subst(uint32_t applicationLevels, uint32_t constructorLevels, Freedom application,
        Freedom constructor, Opacity opacity, mlir::Attribute own);

  mlir::Attribute ownGroup() const { return own; }
  Opacity opacity() const { return opaque; }

  std::optional<Bound> lookup(Side side, uint64_t level) const;
  bool isFree(Side side) const;
  void bind(Side side, uint64_t level, Bound to);

  // The binding of constructor level `level`, resolved through levels bound
  // in turn, or none when it is unbound.
  std::optional<Bound> resolved(Side side, uint64_t level) const;

  // Writes `term` of `side` with every bound level replaced by its binding:
  // the instance of a field's index under the bindings. A level left
  // unbound is written as itself, shifted by `shift` on the constructor
  // side (its level in the scope it is written into); a null group is
  // written as the group it stands for, since the term leaves its
  // declaration. Says whether an unbound constructor level was written.
  Instance write(TermWriter &out, Term term, Side side, uint32_t shift) const;

private:
  llvm::SmallVector<std::optional<Bound>> application, constructor;
  Freedom applicationFreedom, constructorFreedom;
  Opacity opaque;
  mlir::Attribute own;
};

// The answer of a unification: a clash, so the case does not exist; or the
// substitution, extended.
enum class Unified : uint8_t { Clash, Consistent };

// Unifies `a` (of side `sa`) with `b` (of side `sb`) under `subst`,
// extending it.
Unified unify(Subst &subst, Term a, Side sa, Term b, Side sb);

// Unifies the `count` terms of `application` with those of `equation`, in
// order.
Unified unifyAll(Subst &subst, llvm::ArrayRef<TermNode> application,
                 llvm::ArrayRef<TermNode> equation, size_t count);

} // namespace idr::families

#endif // IDR_IR_FAMILIES_UNIFY_H
