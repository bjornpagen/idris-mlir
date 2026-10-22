// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What the skeleton rules of the matches and the join points share
// (IdrisMLIR.Spec.Control.Rules, declared in idr/IR/Control/Control.h): an
// op remade with fewer results, and the lifetimes it states for them; what
// follows an op that never gives control back; what the e-graph knows of a
// value's constructor. Each rule family is its own unit: MatchRules.cpp,
// IdenticalRegions.cpp, YieldedFields.cpp, CaseOfCase.cpp, JoinRules.cpp.
#ifndef IDR_TRANSFORMS_JOINS_RULES_H
#define IDR_TRANSFORMS_JOINS_RULES_H

#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/EGraph.h"

#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/BitVector.h"
#include "llvm/ADT/SmallVector.h"

#include <optional>

namespace idr::control {

// Whether `region` gives its op's results: it ends in a yield.
bool yields(mlir::Region &region);

// `op` made again with results of `types`, its operands, properties and
// regions moved over, at the rewriter's insertion point. It states the
// lifetimes `op` states: a caller that changes which results are scoped
// restates them.
mlir::Operation *withResults(mlir::RewriterBase &rewriter, mlir::Operation *op,
                             mlir::TypeRange types);

// Removes the results of `op` that `keep` leaves out, from the op, from
// each of its regions' yields, and from the lifetimes it states.
mlir::Operation *keepResults(mlir::RewriterBase &rewriter, mlir::Operation *op,
                             const llvm::BitVector &keep);

// A match none of whose regions yields gives nothing: its results go, what
// follows it in its block is dead, and the block ends in ub.unreachable.
void exits(mlir::RewriterBase &rewriter, mlir::Operation *op);

// The results of `op` no op uses, by position.
llvm::SmallVector<unsigned, 4> unusedResults(mlir::Operation *op);

// Each result of `op` at a position of `chosen` that no op uses still goes,
// from the op and from every yield that gives it.
void dropUnused(mlir::RewriterBase &rewriter, mlir::Operation *op,
                llvm::ArrayRef<unsigned> chosen);

// How many of `op`'s results are scoped: the entries of `outers` before
// those of what its regions bind.
unsigned scopedResultCount(mlir::Operation *op);

// The rule's choice of what it found, the positions its rewrite carries
// out on the root as it then is; nothing where it found none.
std::optional<egraph::Edit> choose(llvm::SmallVector<unsigned, 4> found);

// An idr.data.con among the members of `value`'s class, one computable
// wherever the class is used, seen through a reindex that only changes its
// type (a yield gives a match's results at their own types, so a
// constructor an arm built leaves it cast); a cast of a cast is one, so one
// step suffices. Null where no member is one.
DataConOp constructorOf(mlir::Value value, const egraph::OperandFacts &facts);

// Whether `value` has a known constructor in what the e-graph chose for
// it: a constant constructor, or a value an idr.data.con made.
bool knownConstructor(mlir::Value value, const egraph::OperandFacts &facts);

} // namespace idr::control

#endif // IDR_TRANSFORMS_JOINS_RULES_H
