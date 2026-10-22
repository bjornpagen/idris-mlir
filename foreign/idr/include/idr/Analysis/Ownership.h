// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What counting decides by marking the program before it rewrites a
// function, each an analysis the program's analysis manager caches and
// each answer written into the types by the step that reads it:
//   - Exclusivity: which counted values hold the only reference to every
//     cell they reach (`unique deep`), by context: a function is solved
//     once for each set of followed parameters its callers give it
//     exclusive, and a context whose answer differs from the general one
//     becomes a grade copy of its function;
//   - Borrows: which parameters are views of their caller's value, counted
//     nothing, and which are counted, under the frame-limited rule.
// The in-place promise has no analysis here: idr-in-place decides it on the
// program as written and leaves its verdict in the types
// (idr/Transforms/InPlace.h).
//
// Each analysis reads the program graph for calls and keeps nothing keyed
// by an IR pointer; its state is bits over dense numbers, sized by the
// problem, in the shared containers whose bytes a pass's footprint counts.
//
// Exclusivity's domain is what QTT and freshness do not settle: a value the
// local rule proves `unique deep` (idr-unique-results, before
// bufferization) is typed so when the solve runs, and neither a value whose
// type answers nor one an op of upstream's reads at its bare grade is
// followed by any marking.
#ifndef IDR_ANALYSIS_OWNERSHIP_H
#define IDR_ANALYSIS_OWNERSHIP_H

#include "idr/Analysis/Solver/ProgramGraph.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Id.h"

#include "mlir/IR/Operation.h"
#include "mlir/Pass/AnalysisManager.h"
#include "mlir/Support/LogicalResult.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/SmallBitVector.h"

#include <cstdint>

namespace idr {

namespace exclusivity {
// A followed value of one body, by its position in the one walk
// (forEachFollowed): numbered by the walk, so the solve and the step that
// writes its answer mint the same ids.
struct FollowedNumbers;
struct FollowedTag {
  using Minter = FollowedNumbers;
};
using Followed = Id<FollowedTag>;
struct FollowedNumbers {
  static Followed at(std::uint32_t n) { return Followed(n); }
  static Count<Followed> count(std::uint32_t n) { return Count<Followed>(n); }
};
} // namespace exclusivity

// Exclusivity of the counted values of a program, solved by context and
// frozen. A context is a function with the followed parameters it takes
// exclusive (its key); every function has its general context, which takes
// none and which its original symbol keeps, and a call that gives exclusive
// values at some followed parameters reaches the context of exactly those.
// Each context's answer is a bit per followed value of its function, in the
// order the one walk of a body gives them (exclusivity::forEachFollowed), so
// a copy, a clone of its original, reads the same numbering. Contexts whose
// answers are equal are one version of the function.
class Exclusivity {
public:
  using FunctionId = solver::FunctionId;

  // One version of a function: the followed parameters it takes exclusive
  // (empty for the general version, which the original symbol keeps), the
  // exclusive followed values of its body, whether each result is
  // exclusive, and the version of its callee each of its calls goes to, in
  // the walk's order of calls.
  struct Version {
    llvm::SmallBitVector key;
    BitSet<exclusivity::Followed> exclusive;
    llvm::SmallBitVector results;
    footprint::Vector<std::uint32_t> callTargets;
  };

  // The solve of `program`, reading its program graph from `am`.
  Exclusivity(mlir::Operation *program, mlir::AnalysisManager &am);

  bool isInvalidated(const mlir::AnalysisManager::PreservedAnalyses &pa) const {
    return !pa.isPreserved<Exclusivity>() || !pa.isPreserved<solver::ProgramGraph>();
  }

  // The versions of `fn`: the general one first, then each copy, in the
  // order the solve made their contexts.
  llvm::ArrayRef<Version> versions(FunctionId fn) const { return versionsOf[fn]; }

  // What the solve measured: contexts reached, copies kept, rounds of
  // marking with targets fixed, and the nodes and edges its markings read.
  unsigned contexts() const { return numContexts; }
  unsigned copies() const { return numCopies; }
  unsigned rounds() const { return numRounds; }
  std::uint64_t work() const { return numWork; }

  // Whether a body broke the representation's invariant (a terminator with
  // block successors before the lowering), reported at the op: the
  // compiler's bug, for the pass that asked to fail with.
  bool brokeInvariant() const { return mlir::failed(read); }

private:
  IndexVector<FunctionId, footprint::Vector<Version>> versionsOf;
  unsigned numContexts = 0;
  unsigned numCopies = 0;
  unsigned numRounds = 0;
  std::uint64_t numWork = 0;
  mlir::LogicalResult read = mlir::success();
};

// Borrow inference: each parameter that holds references, of a function or
// of a join point, is a view of its caller's value (`scoped`, counted
// nothing) or `counted`, the grade's own release axis. Counted is forced
// where the callee consumes any part of the parameter: returns, stores,
// releases or takes apart (a rebuild site among those) the parameter or a
// value read from it, or passes one to a counted parameter, since what is
// read from a view is a view and no view is consumed (an element loaded
// from an array takes its own reference where it is read, and consuming it
// consumes nothing of the array), or an op of upstream's reads it or a part
// of it, which takes only the bare carrier; and wherever a caller's
// argument is bound at quantity 1, or is dead after the call while its type
// does not bound what it reaches, or is passed where no loan of it may
// stand: by a tail call or a call modulo context (a jump is a tail
// transfer), by a call on its caller's own cycle, or by a jump into a join
// point whose op holds one, since frames split a function at such a call.
// The root's parameters are counted (its caller is outside); a memo cell's
// are views (a force writes it while its caller reads it).
class Borrows {
public:
  using FunctionId = solver::FunctionId;

  Borrows(mlir::Operation *program, mlir::AnalysisManager &am);

  bool isInvalidated(const mlir::AnalysisManager::PreservedAnalyses &pa) const {
    return !pa.isPreserved<Borrows>() || !pa.isPreserved<solver::ProgramGraph>();
  }

  // The release of parameter `index` of `fn`, one that holds references:
  // Counted or Scoped.
  Release parameter(FunctionId fn, unsigned index) const { return released[fn][index]; }
  // The release of join parameter `index` of `fn`, numbered in the order
  // borrows::forEachJoinParameter gives them.
  Release joinParameter(FunctionId fn, unsigned index) const { return joinReleased[fn][index]; }
  // How many parameters are views.
  unsigned views() const { return numViews; }

private:
  IndexVector<FunctionId, footprint::Vector<Release>> released;
  IndexVector<FunctionId, footprint::Vector<Release>> joinReleased;
  unsigned numViews = 0;
};

} // namespace idr

#endif // IDR_ANALYSIS_OWNERSHIP_H
