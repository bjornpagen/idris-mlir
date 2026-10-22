// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Grade copies: the finite alphabet the specializer's one clone-and-key
// template is instantiated with where a function is copied for the sharing
// its callers can give it (idr-rc-exclusive's contexts) or must be given
// back (idr-in-place's results). A key is its owner and, per parameter the
// claim the copy takes it at and per result the claim it gives, compared
// by equality and never lifted: an owner has at most one copy per key, and
// the keys of an owner are finite. The copy is its owner's clone, every
// grade its owner's; the pass that keyed it writes the key's claims into
// its values once every version is made.
#ifndef IDR_ANALYSIS_OWNERSHIP_GRADECOPIES_H
#define IDR_ANALYSIS_OWNERSHIP_GRADECOPIES_H

#include "idr/Analysis/Solver/ProgramGraph.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Specialize.h"

#include "mlir/IR/SymbolTable.h"
#include "llvm/ADT/SmallVector.h"

#include <iterator>

namespace idr::ownership {

// The alphabet, one per pass that keys copies, so the copies of one owner
// by two passes are named apart: `Name::kind` is the kind in the copy's
// name.
template <class Name>
struct GradeCopies {
  struct Key {
    solver::FunctionId owner;
    llvm::SmallVector<Unique, 4> params;
    llvm::SmallVector<Unique, 2> results;
  };
  using Order = specialize::Equality;
  static constexpr llvm::StringLiteral kind = Name::kind;

  static solver::FunctionId owner(const Key &key) { return key.owner; }
  // One word per letter, the parameters' count first, then the results'.
  static void write(const Key &key, specialize::Bytes &bytes) {
    bytes.word(key.params.size());
    for (Unique claim : key.params)
      bytes.word(static_cast<std::uint64_t>(claim));
    bytes.word(key.results.size());
    for (Unique claim : key.results)
      bytes.word(static_cast<std::uint64_t>(claim));
  }
  // The claims are written by the pass that keyed the copy, over every
  // version at once, so the clone is the copy as made.
  static mlir::LogicalResult edit(const Key &, FuncOp) { return mlir::success(); }
};

// idr-rc-exclusive's contexts, and idr-in-place's results.
struct ContextCopy {
  static constexpr llvm::StringLiteral kind = "exclusive";
};
struct PromiseCopy {
  static constexpr llvm::StringLiteral kind = "promise";
};
using ContextCopies = GradeCopies<ContextCopy>;
using PromiseCopies = GradeCopies<PromiseCopy>;

// The copy of `owner` that `key` names, right after its owner, through the
// program's symbol table. A pass makes each key of an owner once, so a name
// the table already holds is another key's: the compiler's error, never a
// renamed copy.
template <class Alphabet>
mlir::FailureOr<FuncOp> gradeCopy(FuncOp owner, const typename Alphabet::Key &key,
                                  mlir::SymbolTable &symbols) {
  mlir::StringAttr name = specialize::nameOf<Alphabet>(owner.getSymNameAttr(), key);
  if (symbols.lookup(name))
    return owner.emitOpError("internal error: the grade copy's name @")
           << name.getValue() << " is another function's";
  // A grade copy's edit cannot fail: it changes nothing of the clone.
  mlir::FailureOr<FuncOp> copy = specialize::makeCopy<Alphabet>(owner, key, name);
  symbols.insert(*copy, std::next(owner->getIterator()));
  return copy;
}

} // namespace idr::ownership

#endif // IDR_ANALYSIS_OWNERSHIP_GRADECOPIES_H
