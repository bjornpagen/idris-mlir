// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The one substitution of index terms, which the verifier, the specializer,
// a fold that inlines a case, the inliner and contification share: a type
// with levels replaced by terms, a constructor's fields at an application,
// a function's binders replaced by a call's terms (each case the new
// indices make impossible pruned in the same rewrite), and a region's
// levels renumbered where it moves to another depth. Every type is mapped
// by upstream's AttrTypeReplacer; index terms are written in normal form.
#ifndef IDR_IR_FAMILIES_SUBSTITUTE_H
#define IDR_IR_FAMILIES_SUBSTITUTE_H

#include "idr/IR/Families/Families.h"

#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Region.h"

namespace idr {

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
// `binders`: what a case binds and idr.field reads.
llvm::SmallVector<mlir::Type> instantiateFields(FamilyAttr group, llvm::ArrayRef<mlir::Type> fields,
                                                llvm::ArrayRef<Term> binders);

// `type`, a callee's signature or one of its types, at a call's terms
// `args`: each binder whose term is opaque stays a binder, renumbered among
// those that stay; every other is replaced by its term.
mlir::Type substitute(mlir::Type type, IndexArgsAttr args);
mlir::FunctionType substitute(mlir::FunctionType type, IndexArgsAttr args);

// The function `function` (its signature and its body) instantiated at
// `args`, as `substitute` maps a type, every case region the new indices
// make impossible pruned and every refinement cast between two types that
// became equal folded. The sorts of the binders that stay, which the caller
// sets on its op.
mlir::FailureOr<llvm::SmallVector<Sort>> substituteFunction(mlir::Operation *function,
                                                            llvm::ArrayRef<Sort> binders,
                                                            IndexArgsAttr args);

// Moves the levels [from, from + count) of every type under `region` to
// [to, to + count), and every level past them by as much: what a function
// body becomes as a join region at another depth.
void renumber(mlir::Region &region, uint32_t from, uint32_t count, uint32_t to);

// A call's terms naming levels [first, first + count) of the caller, in
// order: a body entered with its own binders.
IndexArgsAttr levelArgs(mlir::MLIRContext *context, uint32_t first, uint32_t count);

// `count` opaque terms: every binder stays.
IndexArgsAttr opaqueArgs(mlir::MLIRContext *context, uint32_t count);

// The layout class a call's terms give its callee: each term that turns a
// type of the signature into an application whose class is closed kept,
// each other opaque; none when no type of the signature changes its layout,
// so the call needs no copy. The class set is finite under the shape
// budget, so the copies are, and specialization ends by construction.
std::optional<IndexArgsAttr> classesUnder(mlir::FunctionType signature, IndexArgsAttr args);

} // namespace families
} // namespace idr

#endif // IDR_IR_FAMILIES_SUBSTITUTE_H
