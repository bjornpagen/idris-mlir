// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The one substitution of index terms, which the verifier, the specializer,
// a fold that inlines a case, the inliner and contification share: a type
// with levels replaced by terms, a constructor's fields at an application,
// a function's binders replaced by a call's terms (each case the new
// indices make impossible pruned in the same rewrite, each bare tensor
// argument's axis its extents name made static where its term becomes a
// size, and every type derived from the parameters inferred again), and a
// region's levels renumbered where it moves to another depth. Every type is
// mapped by upstream's AttrTypeReplacer; index terms are written in normal
// form.
#ifndef IDR_IR_FAMILIES_SUBSTITUTE_H
#define IDR_IR_FAMILIES_SUBSTITUTE_H

#include "idr/IR/Families/Families.h"

#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Region.h"

namespace idr {

struct Extent;
class ExtentsAttr;
class FuncOp;
class IndexArgsAttr;

namespace families {

// What becomes of each level of a scope: replaced by a term (of the scope
// it is written into), or kept as a level (perhaps another one).
class LevelMap {
public:
  // Level `level` becomes `term`.
  void replace(uint32_t level, Term term);
  // Level `level` becomes level `to`.
  void renumber(uint32_t level, uint32_t to);
  // Every level from `from` on moves by `by` levels, below the ones named.
  void shiftFrom(uint32_t from, int64_t by);

  // Writes `term` with its levels mapped.
  void write(TermWriter &out, Term term) const;
  // The term level `level` is replaced by, none where it is kept.
  std::optional<Term> replacementOf(uint32_t level) const;
  // Whether no level changes.
  bool isIdentity() const { return replaced.empty() && renumbered.empty() && shift == 0; }

private:
  llvm::SmallVector<std::pair<uint32_t, llvm::SmallVector<TermNode>>> replaced;
  llvm::SmallVector<std::pair<uint32_t, uint32_t>> renumbered;
  uint32_t shiftStart = 0;
  int64_t shift = 0;
};

// `type` with every index term in it mapped: a data type, a natural's
// index, a member of a declaration's own group (which becomes its data type
// where `own` is given, the declaration it leaves), at any depth of the
// type's structure; a data type is made in normal form, so a refinement the
// new indices make empty or whole is normalized with it.
mlir::Type mapLevels(mlir::Type type, const LevelMap &map, FamilyAttr own = FamilyAttr());

// The fields of a constructor declared in `group` at the binders' terms
// `binders`: what a case binds and idr.data.field reads.
llvm::SmallVector<mlir::Type> instantiateFields(FamilyAttr group, llvm::ArrayRef<mlir::Type> fields,
                                                llvm::ArrayRef<Term> binders);

// `type`, a callee's signature whose extents are `extents` (null for none),
// at a call's terms `args`: each binder replaced by its term, which is what
// the binder becomes in the scope the signature is read in, the one meaning
// a term has wherever substitution reads it. At a call the scope is the
// caller's, where an opaque term is an index the language cannot express,
// as Emit writes `_`; at a copy it is the copy's own, where a binder that
// stays is the level it becomes there, the k-th kept being level k. Each
// axis an extent names is static where staticSizeAt gives its term a
// size, a bare tensor argument's, the rule idr.func's verifier reads too. A
// result keeps the callee's type, and a graded array its `?`. It is the
// signature substituteFunction gives the callee's copy at `args`, both read
// off one mapping, so a call's view of a copy is the copy's type.
mlir::FunctionType substitute(mlir::FunctionType type, ExtentsAttr extents, IndexArgsAttr args);

// The function `function` (its signature, its extents and its body)
// instantiated at `args`, as `substitute` maps its signature, every case
// region the new indices make impossible pruned and every refinement cast
// between two types that became equal folded. Each entry's term is mapped;
// an entry goes where `substitute` makes its axis static or its term
// became opaque, and every other stays, a constant one where the axis
// keeps its `?` (a result, a graded array). The body follows its
// parameters' types in one walk in program order: each op whose results
// follow from its operands has them inferred again wherever they no longer
// agree with its operands, whether an axis was made static here or the
// caller set a parameter's hold before the call. A result's grade follows,
// and its shape only where it is a bare tensor, which tensor.cast takes
// back where a use's type is fixed elsewhere; a graded value keeps its
// shape, since no cast keeps a grade, and an op that accepts a graded
// result only at the refined shape reads its operands through their casts
// back instead. `args` is a copy's key, each term closed or the level its
// binder becomes in the copy, which keeps it. The sorts of the binders that
// stay, which the caller sets on its op.
mlir::FailureOr<llvm::SmallVector<Sort>> substituteFunction(FuncOp function, IndexArgsAttr args);

// Moves the levels [from, from + count) of every type under `region` to
// [to, to + count), and every level past them by as much: what a function
// body becomes as a join region at another depth.
void renumber(mlir::Region &region, uint32_t from, uint32_t count, uint32_t to);

// A call's terms naming levels [first, first + count) of the caller, in
// order: a body entered with its own binders; and, from 0, the key of a
// copy that keeps every binder.
IndexArgsAttr levelArgs(mlir::MLIRContext *context, uint32_t first, uint32_t count);

// `count` opaque terms: indices the language cannot express, as an
// application at unknown indices has them.
IndexArgsAttr opaqueArgs(mlir::MLIRContext *context, uint32_t count);

// The layout class a call's terms give its callee, `extents` the entries
// of the callee's extents a size may key a copy at, in (side, position,
// axis) order, as the key of the copy at that class: each term that turns
// a type of the signature into an application whose class is closed kept,
// and each that makes an axis static by staticSizeAt; each other binder
// stays, the level it becomes in the copy; none when no type of the
// signature changes its layout, so the call needs no copy. The entries are
// views of the terms the callee's attribute owns, so a caller that keys on
// some of them filters them with no attribute made.
std::optional<IndexArgsAttr> classesUnder(mlir::FunctionType signature,
                                          llvm::ArrayRef<Extent> extents, IndexArgsAttr args);

} // namespace families
} // namespace idr

#endif // IDR_IR_FAMILIES_SUBSTITUTE_H
