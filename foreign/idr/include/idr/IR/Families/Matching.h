// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// One type against another with the levels of the second instantiated by
// one substitution, consistently through the whole type, in progress: the
// state a pattern type reads as it matches an instance of its own class
// (PatternTypeInterface::matchInstance), which compares index terms under
// the substitution being built and queues the parts the pair holds, so a
// type nests as deep as the program writes it and the match's depth is
// none of it.
#ifndef IDR_IR_FAMILIES_MATCHING_H
#define IDR_IR_FAMILIES_MATCHING_H

#include "idr/IR/Families/Families.h"
#include "idr/IR/Families/Unify.h"

#include "mlir/IR/Types.h"
#include "llvm/ADT/SmallVector.h"

#include <cstddef>
#include <cstdint>
#include <optional>

namespace idr::families {

class PatternMatch {
public:
  explicit PatternMatch(Narrowing narrowing);

  // Whether `instance` is `pattern` under the substitution being built: the
  // pattern's levels free, the instance's fixed, each of its terms read as
  // readInstance reads it.
  bool match(mlir::Type pattern, mlir::Type instance);

  // Whether `count` terms of the pattern are those of the instance under
  // the substitution, which they extend.
  bool terms(llvm::ArrayRef<TermNode> pattern, llvm::ArrayRef<TermNode> instance, std::size_t count);

  // The instance's `count` index terms as the match reads them against the
  // pattern's, where it reads them otherwise than as written: where
  // narrowing is allowed (a refinement), each term holding an index Idris
  // proved and the language cannot write is taken for the pattern's term
  // there, its levels moved past the instance's `levels`; none where every
  // term is read as written, as an instance of a pattern reads each.
  std::optional<llvm::SmallVector<TermNode>> readInstance(llvm::ArrayRef<TermNode> pattern,
                                                          llvm::ArrayRef<TermNode> instance,
                                                          std::size_t count,
                                                          std::uint32_t levels) const;

  // Whether the pair being matched may narrow: a data type at the top of a
  // value's type, where narrowing is allowed; one inside another type may
  // not, since only a case's scrutinee is refined.
  bool mayNarrow() const;

  // A pair of parts the pair being matched holds, met where it is.
  void queue(mlir::Type pattern, mlir::Type instance);

private:
  // Where a type is met: at the top of a value's type, or inside another.
  enum class Depth : std::uint8_t { Top, Inner };
  struct Pair {
    mlir::Type pattern;
    mlir::Type instance;
    Depth depth;
  };

  bool step(const Pair &pair);

  Narrowing narrowing;
  Subst subst;
  Depth at = Depth::Top;
  llvm::SmallVector<Pair> pending;
};

} // namespace idr::families

#endif // IDR_IR_FAMILIES_MATCHING_H
